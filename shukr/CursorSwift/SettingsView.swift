import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    /// The header's back chevron. Passed in rather than read from `sharedState`, so this big
    /// Form doesn't re-render on every page turn (it only ever wrote `horizontalPage`).
    var onBack: () -> Void = {}
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    
    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 9
    // The compass reads this from the app-group suite (QiblaSettings); writing it to the standard
    // suite here is why the stepper never changed anything.
    @AppStorage("qibla_sensitivity", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var qiblaSensitivity: Double = 3.5
    
    @AppStorage("fajrNotif") var fajrNotif: Bool = true
    @AppStorage("dhuhrNotif") var dhuhrNotif: Bool = true
    @AppStorage("asrNotif") var asrNotif: Bool = true
    @AppStorage("maghribNotif") var maghribNotif: Bool = true
    @AppStorage("ishaNotif") var ishaNotif: Bool = true

    @AppStorage("fajrNudges") var fajrNudges: Bool = true
    @AppStorage("dhuhrNudges") var dhuhrNudges: Bool = true
    @AppStorage("asrNudges") var asrNudges: Bool = true
    @AppStorage("maghribNudges") var maghribNudges: Bool = true
    @AppStorage("ishaNudges") var ishaNudges: Bool = true
    
    @AppStorage("didShowAlarmSetupAlert") private var didShowAlarmSetupAlert: Bool = false
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmEnabled: Bool = false
        
//    @AppStorage("calculationMethod") var calculationMethod: Int = 2
//    @AppStorage("school") var school: Int = 0
    @AppStorage("calculationMethod", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var calculationMethod: Int = 2
    @AppStorage("school", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var school: Int = 0

    
    @AppStorage("modeToggle") var colorModeToggle = false
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased
    
    @AppStorage("lastLatitude", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastLatitude: Double = 0
    @AppStorage("lastLongitude", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var lastLongitude: Double = 0
    
    @AppStorage("prayerStreakMode") var prayerStreakMode: Int = 1 //prayerstreak_flag
    @State private var isNotifPopupVisible: Bool = false
    @State private var isStreakPopupVisible: Bool = false
    
    @State private var rotationAngle: Double = 0 // For rotating the symbol
    
    // for the floating message
    @State private var showFloatingMessage = false // State to control visibility
    
    // For minimizing and expanding the devSection
    @State private var showDevStuff = false
    @State private var showCityPicker = false
    @AppStorage("tasbeehRingStyle") private var tasbeehRingStyle = TasbeehRingStyle.alive.rawValue
    @State private var showRingPlayground = false
    @AppStorage(ZikrWheelStyle.key) private var zikrWheelStyle = ZikrWheelStyle.gentle.rawValue
    @AppStorage(MosqueIconStyle.key) private var mosqueIconStyle = MosqueIconStyle.finder.rawValue
    @AppStorage(PostSalahPromptStyle.key) private var postSalahPromptStyle = PostSalahPromptStyle.nudge.rawValue

    // For choosing the sheet's content when clicking on the sneak peek stuff
    @State private var selectedUpcomingFeature: sneakPeekItem?
    @State private var showFeatureSheet: Bool = false

    // Create an array of sneakPeekItems.
    let upcomingFeatures: [sneakPeekItem] = [
        sneakPeekItem(image: "map", title: "Masjid Map", description: "For those times you're in another city and need to find a mosque, this will come in handy!"),
        sneakPeekItem(image: "lightbulb.max.fill", title: "Hadith Motivator", description: "Sometimes we lose sight of the intention behind our actions and just go through the motions. A daily Hadith page would be a cool way to stay reminded of our purpose in this dunya"),
        sneakPeekItem(image: "fork.knife", title: "Food Finder", description: "Finding food is hard. Finding halal food - even harder. I wanna partner with another organization for this iA (cough cough HalalEatsNC?!)"),
        sneakPeekItem(image: "character.book.closed", title: "Quranic Vocab", description: "Explore and learn common words from the Quran to make it easier to focus during prayer."),
        sneakPeekItem(image: "gift", title: "Sadaqah Links", description: "A list of trustworthy links to help the ummah. Ideally, Apple Pay integration and donation history in app would be nice!")
    ]
    
    // Define a model for each suggestion.
    struct sneakPeekItem: Identifiable {
        let id = UUID()
        let image: String
        let title: String
        let description: String
    }
    
    let calculationMethods = [
        (1, "University of Islamic Sciences, Karachi"), // .karachi
        (2, "Islamic Society of North America"), // .northAmerica
        (3, "Muslim World League"), // .muslimWorldLeague
        (4, "Umm Al-Qura University, Makkah"), // .ummAlQura
        (5, "Egyptian General Authority of Survey"), // .egyptian
        (7, "Institute of Geophysics, University of Tehran"), // .tehran
        (8, "Gulf Region"), // .dubai
        (9, "Kuwait"), // .kuwait
        (10, "Qatar"), // .qatar
        (11, "Majlis Ugama Islam Singapura, Singapore"), // .singapore
        (12, "Union Organization islamic de France"), // .other
        (13, "Diyanet İşleri Başkanlığı, Turkey"), // .turkey
        (14, "Spiritual Administration of Muslims of Russia") // .other
    ]
    
    let schools = [
        (0, "Shafi'i"),
        (1, "Hanafi")
    ]
    
    
    
    
    
    
    
    
    
    
    var body: some View {
        ZStack{
            VStack{
                // Page header: back to the main page, title, light/dark/auto toggle.
                HStack {
                    Button(action: {
                        onBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Text("Settings")
                        .font(.headline)
                    
                    Spacer()
                    
                    ColorModeToggleButton(showFloatingMessage: $showFloatingMessage)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Form {
                    
                    //MARK: - Location Info
                    Section(header: Text("Location Information")) {
                        if let cityName = viewModel.cityName {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                Text("City")
                                Spacer()
                                Text(cityName)
                            }
                        } else {
                            Text("Fetching city...")
                        }
                        
                        HStack {
                            Image(systemName: "arrow.left.and.right.square")
                            Text("Latitude")
                            Spacer()
                            Text(String(format: "%.6f", lastLatitude))
                        }
                        
                        HStack {
                            Image(systemName: "arrow.up.and.down.square")
                            Text("Longitude")
                            Spacer()
                            Text(String(format: "%.6f", lastLongitude))
                        }
                        
                        if envLocationManager.isAuthorized {
                            Button("Refresh Location") {
                                viewModel.refreshCityAndPrayerTimes()
                                viewModel.fetchPrayerTimes(cameFrom: "SettingsView Refresh Location Button")
                            }
                            .tint(.green)
                        } else {
                            // No location permission: prayer times come from a picked city.
                            Button("Choose City") { showCityPicker = true }
                                .tint(.green)
                            Button("Use My Location") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .tint(.green)
                        }
                    }
                    .sheet(isPresented: $showCityPicker) {
                        CityPickerSheet()
                            .environmentObject(envLocationManager)
                    }
                    
                    
                    //MARK: - Notifications
                    Section(header: headerWithInfoButton(title: "Notifications", isPopupVisible: $isNotifPopupVisible) ) {
                        HStack {
                            prayerCol(prayerName: "Fajr", notifIsOn: $fajrNotif, nudgeIsOn: $fajrNudges)
                            Divider()
                            prayerCol(prayerName: "Dhuhr", notifIsOn: $dhuhrNotif, nudgeIsOn: $dhuhrNudges)
                            Divider()
                            prayerCol(prayerName: "Asr", notifIsOn: $asrNotif, nudgeIsOn: $asrNudges)
                            Divider()
                            prayerCol(prayerName: "Maghrib", notifIsOn: $maghribNotif, nudgeIsOn: $maghribNudges)
                            Divider()
                            prayerCol(prayerName: "Isha", notifIsOn: $ishaNotif, nudgeIsOn: $ishaNudges)
                        }
                        .padding(.vertical)
                        
                        if isNotifPopupVisible{
                            NotificationDropdownInfo()
                        }
                    }
                    
                    
                    // MARK: - Daily Alarm
                    AlarmSettingsView()
                    
                    
                    
                    //MARK: - Prayer Streak Settings 
//                    Section(header: headerWithInfoButton(title: "Streak Settings", isPopupVisible: $isStreakPopupVisible) ) { //prayerstreak_flag
//                        Picker("Streak Type", selection: $prayerStreakMode) {
//                            Text("Level 1").tag(1)
//                            Text("Level 2").tag(2)
//                            Text("Level 3").tag(3)
//                        }
//                        .pickerStyle(.segmented)
//                        
//                        if isStreakPopupVisible{
//                            StreakDropdownInfo()
//                        }
//                    }

                    
                    
                    //MARK: - Calculation Method
                    Section(header: Text("Calculation Method")
                        #if DEBUG
                        .onTapGesture {
                            showDevStuff.toggle()
                        }
                        #endif
                    ) {
                        Picker("Method", selection: $calculationMethod) {
                            ForEach(calculationMethods, id: \.0) { method in
                                Text(method.1).tag(method.0)
                            }
                        }
                        Picker("School", selection: $school) {
                            ForEach(schools, id: \.0) { school in
                                Text(school.1).tag(school.0)
                            }
                        }
                        
                        // Qibla sensitivity: ± buttons that repeat (and speed up) while held.
                        HStack {
                            Image(systemName: "location.north.line")
                            Text("Qibla Accuracy: ± \(qiblaSensitivity, specifier: "%.1f")°")
                                .monospacedDigit()
                            Spacer()
                            HoldRepeatStepper(value: $qiblaSensitivity,
                                              in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                                              step: 0.5)
                        }
                        
                    }
                    .onChange(of: calculationMethod) { _, new in
                        viewModel.fetchPrayerTimes(cameFrom: "onChange calculationMethod")
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    .onChange(of: school) { _, new in
                        viewModel.fetchPrayerTimes(cameFrom: "onChange school")
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    
                    
                    
                    //MARK: - Suggestions / Up and Coming
//                    Section(header: Text("Sneak Peek...")) {
//                        
//                        sectionWithChevronButton(image: "map", title: "Masjid Map", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "lightbulb.max.fill", title: "Hadith Motivator", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "fork.knife", title: "Food Finder", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "character.book.closed", title: "Quranic Words", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "gift", title: "Sadqah Links", isPopupVisible: .constant(false))
//                        
//                        sectionWithChevronButton(image: "figure.2.left.holdinghands", title: "Support Muslim Brands", isPopupVisible: .constant(false))
//                        
//                        Button("Suggest Feature") {
//                            // control a popup or send to an external link?
//                        }
//                    }
                    
                    Section(header: Text("Sneak Peek...")) {
                        ForEach(upcomingFeatures) { feature in
                            HStack {
                                Image(systemName: feature.image)
                                    .frame(width: 24)
                                Text(feature.title)
                                Spacer()
                                Button(action: {
                                    // Set the selected suggestion so the sheet appears.
                                    selectedUpcomingFeature = feature
//                                    showFeatureSheet = true
                                }) {
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                    }

                    
                    //MARK: - Dev Stuff
                    #if DEBUG
                    if(showDevStuff){
                        Section(header: Text("My Dev Stuff")) {
                            Picker("Tasbeeh Ring", selection: $tasbeehRingStyle) {
                                ForEach(TasbeehRingStyle.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                            Button("Ring playground…") { showRingPlayground = true }
                            Picker("Zikr wheel", selection: $zikrWheelStyle) {
                                ForEach(ZikrWheelStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            Picker("Post-salah prompt", selection: $postSalahPromptStyle) {
                                ForEach(PostSalahPromptStyle.allCases) { Text($0.title).tag($0.rawValue) }
                            }
                            Picker("Mosque icon", selection: $mosqueIconStyle) {
                                ForEach(MosqueIconStyle.allCases) { style in
                                    Label(style.title, systemImage: style.button(on: false)).tag(style.rawValue)
                                }
                            }
                            Picker("Ring Style", selection: $selectedRingStyle) {
                                ForEach(0..<10) { index in
                                    Text("\(index)").tag(index)
                                }
                                
                            }
                            Toggle("Location Printer", isOn: $viewModel.locationPrints)
                            Toggle("Scheduling Printer", isOn: $viewModel.schedulePrints)
                            Toggle("Calculation Printer", isOn: $viewModel.calculationPrints)
                            VStack{
                                Toggle("Use Test Prayer Times", isOn: $viewModel.useTestPrayers)
                                    .onChange(of: viewModel.useTestPrayers) { _, new in
                                        viewModel.fetchPrayerTimes(cameFrom: "toggle Use Test Prayer Times")
                                    }
                                if viewModel.useTestPrayers {
                                    Text("Using test times with short intervals")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            Button("Reset Autopilot Fajr Alert"){
                                didShowAlarmSetupAlert = false
                                alarmEnabled = false
                            }
                        }

                    }
                    #endif
                    
                }
            }
            floatingMessageView(showFloatingMessage: $showFloatingMessage)
        }
        .sheet(isPresented: $showRingPlayground) { RingPlaygroundView() }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-demoRingPlayground") {
                try? await Task.sleep(for: .seconds(1.5))
                showRingPlayground = true
            }
        }
        #endif
        .sheet(item: $selectedUpcomingFeature) { feature in
            ScrollView{
                VStack(spacing: 10) {
                // Feature image
                Image(systemName: feature.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .symbolRenderingMode(.monochrome) // Makes the SF Symbol render in a single, monochrome color
                    .foregroundColor(.primary) // Use primary or secondary to avoid the default accent color
                    .padding(.top, 20)
                
                // Title
                Text(feature.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                Text(feature.description)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                
                Spacer()
            }
                
            .padding()
            .presentationDetents([.height(300), .medium, .large])
            .presentationDragIndicator(.visible)  // shows the grab handle at the top
            }

        }

        // The status-bar strip above this page is painted by the pager (PrayerTimesAndTracker),
        // because pages are clipped to the pager's frame and can't reach it from here.
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground))
        .navigationBarBackButtonHidden(false)
        
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ColorModeToggleButton(showFloatingMessage: $showFloatingMessage)

            }
        }
        .onDisappear{
            viewModel.fetchPrayerTimes(cameFrom: "onDisappear SettingsView")
        }
    }
    
    
                
    
}


//MARK: - Helper Views

struct floatingMessageView: View {
    @Binding var showFloatingMessage: Bool
    @AppStorage("modeToggleNew") var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = SunBased
    
    private func capsule(for mode: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: mode == 0 ? "sun.max.fill" : mode == 1 ? "moon.fill" : "circle.lefthalf.filled")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.green)
            Text(mode == 0 ? "Light mode" : mode == 1 ? "Dark mode" : "Auto · follows the sun")
                .font(.system(size: 15, weight: .regular, design: .rounded))
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .mapGlass(Capsule())
        .fixedSize()
    }

    var body: some View {
        // Drops in just under the header, right below the toggle that was tapped — at the bottom
        // of the screen it sat on the home indicator and was easy to miss (owner, 2026-09-25).
        VStack{
            // Glass capsule with the mode's symbol (2026-09-25; was an outlined box). One capsule
            // per mode, crossfaded: morphing one capsule's width while its text swapped drew it
            // off-centre for a moment on each switch (owner).
            ZStack {
                ForEach([0, 1, 2], id: \.self) { mode in
                    if mode == colorModeToggleNew {
                        capsule(for: mode)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeInOut(duration: 0.2), value: colorModeToggleNew)
            .opacity(showFloatingMessage ? 1 : 0.0)
            .scaleEffect(showFloatingMessage ? 1 : 0.9, anchor: .top)
            .offset(y: showFloatingMessage ? 0 : -12)
            .padding(.top, 52)
            .zIndex(1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFloatingMessage)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

struct ColorModeToggleButton: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    
    @Binding var showFloatingMessage: Bool
    @State private var dismissWorkItem: DispatchWorkItem? // Manage the dismissal timer

    @AppStorage("modeToggleNew") private var colorModeToggleNew: Int = 0 // 0 = Light, 1 = Dark, 2 = Auto
    
    var body: some View {
        Button(action: toggleColorMode) {
            Image(systemName: currentSymbol)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
        }
    }
    
    /// Computed property for the current SF Symbol
    private var currentSymbol: String {
        switch colorModeToggleNew {
        case 0: return "sun.min" // Light mode
        case 1: return "moon" // Dark mode
        case 2: return viewModel.isDaytime ? "sun.max.circle" : "moon.circle"
        default: return "circle.lefthalf.filled"
        }
    }
    
    /// Toggle color mode and update the rotation angle
    private func toggleColorMode() {
        withAnimation {
            colorModeToggleNew = (colorModeToggleNew + 1) % 3
        }
        showTemporaryMessage(workItem: &dismissWorkItem, boolToShow: $showFloatingMessage, delay: 2)
    }
}


struct headerWithInfoButton: View {
    var image: String? = nil
    let title: String
    @Binding var isPopupVisible: Bool
    var body: some View {
        HStack {
//            Text("Notifications")
            if let imageName = image {
                Image(systemName: imageName)
                    .frame(width: 24)
            }
            Text(title)
            Spacer()
            Button(action: {
                withAnimation {
                    isPopupVisible.toggle()
                }
            }) {
                Image(systemName: /*isPopupVisible ? "xmark.circle" :*/ "info.circle")
                    .foregroundColor(.green)
            }
        }
    }
}

//struct sectionWithChevronButton: View {
//    var image: String? = nil
//    let title: String
//    let description: String
//    @Binding var isPopupVisible: Bool
//    
//    var body: some View {
//        HStack {
////            Text("Notifications")
//            if let imageName = image {
//                Image(systemName: imageName)
//                    .frame(width: 24)
//            }
//            Text(title)
//            Spacer()
//            Button(action: {
//                withAnimation {
//                    isPopupVisible.toggle()
//                }
//            }) {
//                Image(systemName: "chevron.right")
//                    .foregroundColor(.secondary)
//            }
//        }
//        .sheet(isPresented: $isPopupVisible) {
//            VStack {
//                Text(title)
//                    .font(.title)
//                    .padding()
//                Text(description)
//                    .padding()
//                Button("Close") {
//                    isPopupVisible = false
//                }
//                .padding()
//            }
//        }
//    }
//}


struct prayerCol: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    let prayerName: String
    @Binding var notifIsOn: Bool
    @Binding var nudgeIsOn: Bool

    var body: some View {
            // Unified Bell Button
            Button(action:{
                if !notifIsOn {
                    notifIsOn = true
                    nudgeIsOn = false
                } else if notifIsOn && !nudgeIsOn {
                    notifIsOn = true
                    nudgeIsOn = true
                } else {
                    notifIsOn = false
                    nudgeIsOn = false
                }
                performBellVibration()
            }) {
                VStack{
                    Text(prayerName)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    Spacer()
                    
                    Image(systemName: notifIsOn ?  (nudgeIsOn ? "bell.badge.fill" : "bell.fill") : "bell.slash.fill" )
                        .foregroundColor(notifIsOn ? .primary : .gray)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    

                    Spacer()
                    
                    Text(notifIsOn ?  (nudgeIsOn ? "nudge" : "start") : "off" )

                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: notifIsOn) { _, _ in
                viewModel.fetchPrayerTimes(cameFrom: "onChange notifIsOn")
            }
            .onChange(of: nudgeIsOn) { _, _ in
                viewModel.fetchPrayerTimes(cameFrom: "onChange nudgeIsOn")
            }
    }

    private func performBellVibration() {
        let generator1 = UIImpactFeedbackGenerator(style: .medium)
        let generator2 = UIImpactFeedbackGenerator(style: .light)

        generator1.prepare()
        generator2.prepare()

        generator1.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator2.impactOccurred()
        }
    }
}




struct NotificationDropdownInfo: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information:")
            
            HStack{
                Image(systemName: "bell.slash.fill")
                Text("Off: No notifications will be sent for this prayer.")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Image(systemName: "bell.fill")
                Text("Start: You will only receive a notification when the prayer starts.")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Image(systemName: "bell.badge.fill")
                Text("Nudge: If a prayer is not marked complete, you will get extra notifications at 50% and 25% time left.")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
        }
        HStack{

            Text("Test Start")
                .frame(maxWidth: .infinity)
                .onTapGesture{
                    let content = UNMutableNotificationContent()
                    content.categoryIdentifier = "Round1_Snooze" // Associate the category

                    let randPrayerName = viewModel.orderedPrayerNames.randomElement()!
                    content.title = "\(randPrayerName) Time 🟢"
                    content.subtitle = "Pray by \(shortTimePM(Date()))"
                    content.sound = UNNotificationSound.default
                    content.interruptionLevel = .timeSensitive
                    addToNotificationCenterBySeconds(identifier: "test", content: content, sec: 0.1)
                }
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Spacer()
            Divider()
            Spacer()

            Text("Test Nudge")
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    let content = UNMutableNotificationContent()
                    content.categoryIdentifier = "Round1_Snooze" // Associate the category

                    let randPrayerName = viewModel.orderedPrayerNames.randomElement()!
                    let randNudge = [
                        (title: "\(randPrayerName) At Midpoint 🟡", subtitle: "Did you pray? There's \(timeLeftString(from: Double.random(in: 60...110)*60))"),
                        (title: "\(randPrayerName) Almost Over! 🔴", subtitle: "Did you pray? There's still \(timeLeftString(from: Double.random(in: 20...45)*60))")
                    ]
                        .randomElement()!
                    content.title = randNudge.title
                    content.subtitle = randNudge.subtitle
                    content.sound = UNNotificationSound.default
                    content.interruptionLevel = .timeSensitive
                    addToNotificationCenterBySeconds(identifier: "test", content: content, sec: 0.1)
                }
                .font(.subheadline)
                .foregroundColor(.gray)

        }
        .padding(.horizontal)

    }
    
    func addToNotificationCenterBySeconds(identifier: String, content: UNMutableNotificationContent, sec: Double){
        let center = UNUserNotificationCenter.current()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: sec, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Error \(identifier): \(error.localizedDescription)")
            }
        }
        print("✅ Scheduled \(identifier): in \(sec)s")
    }
}

struct StreakDropdownInfo: View {
    var body: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Information:")
            
            HStack{
                Text("Level 1: Counts kazas")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Text("Level 2: counts prayers completed during prayer window")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack{
                Text("Level 3: counts prayers before 75% of time")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
        }
    }
}


struct AlarmSettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    
    // Whether or not to show the informational text section
    @State private var isAlarmInfoVisible: Bool = false
    
    // Local state to manage alert presentation
    @State private var isShowingShortcutAlert: Bool = false
    
    // To minimize the editing basically
    @State private var isEditingAlarm: Bool = false
    
    // For reference and shown at bottom while setting the alarm
    @State private var nextFajrTime: Date = Date()
    @State private var nextSunriseTime: Date = Date()
    
    // Persisted state (using AppStorage so the values remain between launches)
    @AppStorage("alarmEnabled", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmEnabled: Bool = false
    
    @AppStorage("alarmOffsetMinutes", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmOffsetMinutes: Int = 0
    @AppStorage("alarmIsBefore", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmIsBefore: Bool = true
    @AppStorage("alarmIsFajr", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) var alarmIsFajr: Bool = true
    @AppStorage("alarmTimeSetFor", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var alarmTimeSetFor: String = ""
    @AppStorage("alarmDescription", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) private var alarmDescription: String = ""
    
    // A flag to remember if user has already seen the “setup required” alert
    @AppStorage("didShowAlarmSetupAlert") private var didShowAlarmSetupAlert: Bool = false
    
    // ------------------------------------------
    // MARK: - Computed Helpers
    // ------------------------------------------
    
    /// Checks if the user has *actually* chosen “After Sunrise” (which is disallowed).
    private var isAlarmAfterSunrise: Bool {
        // isBefore = false => After
        // isFajr = false => Sunrise
        return (!alarmIsBefore && !alarmIsFajr)
    }
    
    private var shortcutURL: URL? {
        
        if let url = URL(string: "https://www.icloud.com/shortcuts/6ebcfeb12813483992687461d027fd14"){
            return url
        }
        else {
            return nil
        }
    }
    
    private var timeOfCalcAlarmText: String {
        let ref = alarmIsFajr ? nextFajrTime : nextSunriseTime
        let offsetSeconds = alarmIsBefore ? -Double(alarmOffsetMinutes)*60 : Double(alarmOffsetMinutes)*60
        let calcDate = ref.addingTimeInterval(offsetSeconds)
        return "is \(shortTimePM(calcDate))"
//        return "\(shortTime(alarmIsFajr ? nextFajrTime : nextSunriseTime)) \(alarmIsBefore ? "-" : "+") \(alarmOffsetMinutes)m = \(shortTimePM(calcDate))"
//        return "is \(shortTimePM(calcDate))"
//        return alarmIsFajr ? "\(shortTimePM(calcDate)) (Fajr is at \(shortTimePM(nextFajrTime)))" : "\(shortTimePM(calcDate)) (Sunrise at \(shortTimePM(nextSunriseTime)))"
//        return "\(shortTimePM(calcDate))"
    }
    
    private var fajrTimeRangeText: String {
//        return "(Fajr is \(shortTime(nextFajrTime)) - \(shortTimePM(nextSunriseTime)))"
//        return alarmIsFajr ? shortTimePM(nextFajrTime) : shortTimePM(nextSunriseTime)
        return alarmIsFajr ? "(Fajr is \(shortTimePM(nextFajrTime)))" : "(Sunrise is \(shortTimePM(nextSunriseTime)))"
    }
    
    // ------------------------------------------
    // MARK: - Body
    // ------------------------------------------
    
    var body: some View {
        
        Section(header:
                    HStack {
            Text("Alarm Settings")
            Spacer()
            Button(action: {
                withAnimation {
                    isAlarmInfoVisible.toggle()
                }
            }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.green)
            }
        }
        ) {
            
            // Toggle to enable/disable alarm
            HStack {
                Image(systemName: "alarm")
//                    .foregroundColor(.gray)
                
                Toggle("Schedule Daily Fajr Alarm", isOn: Binding(
                    get: { self.alarmEnabled },
                    set: { newValue in
                        // Animate changes
                        withAnimation {
                            self.alarmEnabled = newValue
                        }
                        // If user just turned it ON and has never seen the alert, show it now
                        if newValue && !didShowAlarmSetupAlert {
                            isShowingShortcutAlert = true
                            didShowAlarmSetupAlert = true
                        }
                    }
                ))
            }
            // Present an alert the first time user toggles the alarm ON
            .alert("Shortcut Required", isPresented: $isShowingShortcutAlert) {
                Button("Get Shortcut") {
                    if let shortcutURL {
                        UIApplication.shared.open(shortcutURL)
                    }
                }
                Button("Cancel", role: .cancel) {
                    didShowAlarmSetupAlert = false
                    alarmEnabled = false
                }
            } message: {
                Text("This only works if you set up a shortcut automation. Tap “Get Shortcut” to install it, then tap the info button above for setup steps.")
            }
            
            // If alarm is enabled, show the detail controls
            if alarmEnabled {
                if isEditingAlarm{
                    VStack{
                        
                        HStack {
                            Picker("", selection: $alarmOffsetMinutes) {
                                ForEach(0...60, id: \.self) { number in
                                    Text("\(number) min")
                                }
                            }
                            .pickerStyle(.wheel)
                            
                            // Picker for "Before"/"After"
                            Picker("", selection: $alarmIsBefore) {
                                Text("Before").tag(true)
                                // Only show "After" if user picked Fajr
                                if alarmIsFajr {
                                    Text("After").tag(false)
                                }
                            }
                            .pickerStyle(.wheel)
                            
                            // Picker for "Fajr"/"Sunrise"
                            Picker("", selection: $alarmIsFajr) {
                                Text("Fajr").tag(true)
                                // Only show "Sunrise" if user picked "Before"
                                if alarmIsBefore {
                                    Text("Sunrise").tag(false)
                                }
                            }
                            .pickerStyle(.wheel)
                            
                        }
                        .frame(height: 100) // Adjust this value to your preferred height
                        .clipped() // This ensures the picker doesn't overflow its frame
                        
                        Text(timeOfCalcAlarmText)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        
                        Text(fajrTimeRangeText)
                            .foregroundStyle(.secondary.opacity(0.8))
                            .font(.footnote)
                    }
                    
                }
                    
                    Button(action: {
                        withAnimation {
                            isEditingAlarm.toggle()
                            do{
                                let calculatedAlarm = try PrayerUtils.calculateAlarmDescription()
                                let resultTime = calculatedAlarm.time
                                alarmTimeSetFor = shortTimePM(resultTime)
                                alarmDescription = calculatedAlarm.description
                            }
                            catch{
                                print("Error: \(error.localizedDescription)")
                            }
                        }
                    }) {
                        HStack {
                            Text(isEditingAlarm ? "Save" : alarmDescription)
                                .foregroundStyle(isEditingAlarm ? Color.green : Color.gray)
                                .font(isEditingAlarm ? .body.weight(.medium) : .subheadline)
                            Spacer()
                            Image(systemName: isEditingAlarm ? "square.and.arrow.down" : "pencil") // Add the pencil icon here
                                .foregroundStyle(isEditingAlarm ? Color.green : Color.gray) // Match the color with text
                        }
                        .contentShape(Rectangle())   // the whole row taps, not just the text
                    }
                    // Plain: keep our colours and the full-width hit area. iOS 26 restyles a
                    // Form's buttons (tint + label-only hit area), which broke this row's look.
                    .buttonStyle(.plain)
            }
            
            // Info Block
            if isAlarmInfoVisible {
                alarmInfoView
            }
        }
        .onAppear{
            // nil until there's a location (no GPS fix yet at first launch); Settings is mounted
            // at launch, so a force unwrap here crashed the app.
            if let sunrise = viewModel.getNextPrayerTime(for: "sunrise") { nextSunriseTime = sunrise }
            if let fajr = viewModel.getNextPrayerTime(for: "fajr") { nextFajrTime = fajr }
        }
        .onChange(of: alarmEnabled){_, newValue in
                if newValue {
                    isEditingAlarm = true
            }
        }
    }

    // ------------------------------------------
    // MARK: - Info Section
    // ------------------------------------------
    
    /// A quick informational view about how to use the alarm feature and set up the shortcuts.
    @ViewBuilder
    private var alarmInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Information:")
            
            Text("No more mental math to set up daily Fajr alarms! Define your rules once. I'll dynamically set daily Fajr alarms for you!")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "1.circle")
                Text("Add iOS shortcut with button below")
//                Text("Click here to add the iOS shortcut")
                    .font(.caption)
                    .foregroundColor(/*.blue*/ .gray)
//                    .underline()
//                    .onTapGesture {
//                        if let shortcutURL {
//                            UIApplication.shared.open(shortcutURL)
//                        }
//                    }
            }
            .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "2.circle")
                Text("Open the iOS Shortcuts App > Automations Tab > Add New")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "3.circle")
                Text("On the sheet > Select 'Time of Day' > 10:00 PM, Daily > Run Immediately > Select this new shortcut")
                    .font(.caption)
            }
            .foregroundColor(.gray)
            
            Divider()
            
            HStack{

                Text("Add iOS Shortcut")
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        if let shortcutURL {
                            UIApplication.shared.open(shortcutURL)
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)

            }
            .padding(.horizontal)

        }
    }
}


/// A ± control whose buttons repeat while held — one step on touch-down, then after 0.4 s a
/// step every 0.12 s, and after 1.5 s every 0.05 s — for values a long way apart, like the
/// qibla accuracy's 1…15° in 0.5° steps. SwiftUI's Stepper needed a press per step.
struct HoldRepeatStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var timer: Timer?
    @State private var pressedAt: Date?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 0) {
            button("minus", direction: -1)
            Divider().frame(height: 18)
            button("plus", direction: 1)
        }
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        .onDisappear { stop() }
    }

    private func button(_ symbol: String, direction: Double) -> some View {
        let atLimit = direction < 0 ? value <= range.lowerBound : value >= range.upperBound
        return Image(systemName: symbol)
            .font(.body.weight(.medium))
            .foregroundStyle(atLimit ? Color.secondary.opacity(0.4) : Color.primary)
            .frame(width: 44, height: 32)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if pressedAt == nil {                 // touch-down: one step, start repeating
                            pressedAt = Date()
                            bump(direction)
                            start(direction)
                        } else if abs(drag.translation.height) > 12 || abs(drag.translation.width) > 12 {
                            stop()                            // finger drifted: it's a scroll, not a hold
                        }
                    }
                    .onEnded { _ in stop() }
            )
    }

    private func bump(_ direction: Double) {
        let next = min(max(value + direction * step, range.lowerBound), range.upperBound)
        guard next != value else { return }
        value = next
        triggerSomeVibration(type: .light)
    }

    private func start(_ direction: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard let pressedAt else { return }
            let held = Date().timeIntervalSince(pressedAt)
            // 0.4 s grace, then every 0.12 s, then every 0.05 s after 1.5 s.
            let interval: TimeInterval = held < 1.5 ? 0.12 : 0.05
            if held >= 0.4, Int((held - 0.4) / 0.05) % Int(interval / 0.05) == 0 { bump(direction) }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        pressedAt = nil
    }
}
