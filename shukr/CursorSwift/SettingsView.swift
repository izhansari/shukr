import SwiftUI
import SwiftData
import UIKit

//used by pulseCircle
struct QiblaSettings {
    @AppStorage("qibla_sensitivity") static var alignmentThreshold: Double = 3.5
    static let minThreshold: Double = 1.0  // More precise
    static let maxThreshold: Double = 10.0 // More forgiving
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    
    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 9
    @AppStorage("qibla_sensitivity") private var qiblaSensitivity: Double = 3.5
    
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
    @AppStorage("alarmEnabled") private var alarmEnabled: Bool = false
    
//    @State private var refreshID = UUID()
    
    @AppStorage("calculationMethod") var calculationMethod: Int = 2
    @AppStorage("school") var school: Int = 0
    
    @AppStorage("modeToggle") var colorModeToggle = false

    @State private var isPopupVisible: Bool = false
    @State private var selectedPrayerToCancelNudges = "Fajr"
    
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
                    Text(viewModel.latitude)
                }
                HStack {
                    Image(systemName: "arrow.up.and.down.square")
                    Text("Longitude")
                    Spacer()
                    Text(viewModel.longitude)
                }
                Button("Refresh Location") {
                    viewModel.refreshCityAndPrayerTimes()
                    viewModel.fetchPrayerTimes()
                }
            }
            
            //MARK: - Calculation Method
            Section(header: Text("Calculation Method")) {
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
                
                // Qibla sensitivity slider
                VStack(alignment: .leading) {
                    HStack{
                        Image(systemName: "location.north.line")
                        Text("Qibla Sensitivity: \(qiblaSensitivity, specifier: "%.1f")°")
                    }
                    Slider(value: $qiblaSensitivity,
                           in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                           step: 0.5)
                    Text("Lower value = More precise")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .onChange(of: calculationMethod) { _, new in
                viewModel.fetchPrayerTimes()
            }
            .onChange(of: school) { _, new in
                viewModel.fetchPrayerTimes()
            }
            
            
            //MARK: - Notifications
            Section(header: notificationHeader(isPopupVisible: $isPopupVisible)) {
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
                
                if isPopupVisible{
                    NotificationDropdownInfo()
                }
            }
            
            
            //MARK: - Appearance
            Section(header: Text("Appearance")) {
                
                Picker(selection: $colorModeToggle, label:
                        HStack {
                    Image(systemName: "circle.lefthalf.filled")
                    Text("Color Scheme")
                }){
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }


            }
            
            
            // MARK: - Daily Alarm
            AlarmSettingsView()
            
            //MARK: - Dev Stuff
            Section(header: Text("My Dev Stuff")) {
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
                            viewModel.fetchPrayerTimes()
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
                Picker("Cancel nudges for", selection: $selectedPrayerToCancelNudges) {
                    ForEach(viewModel.orderedPrayerNames, id: \.self) { prayer in
                        Text(prayer)
                    }
                }
                Button("Cancel for \(selectedPrayerToCancelNudges)") {
                    viewModel.cancelUpcomingNudges(for: selectedPrayerToCancelNudges) //so it cancels... but when we fetch, we put it right back.
                }
            }
            
        }
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(false)
        .onDisappear{
            viewModel.fetchPrayerTimes()
        }
    }
    
                
    
}


//MARK: - Helper Views

struct notificationHeader: View {
    @Binding var isPopupVisible: Bool
    var body: some View {
        HStack {
            Text("Notifications")
            Spacer()
            Button(action: {
                withAnimation {
                    isPopupVisible.toggle()
                }
            }) {
                Image(systemName: /*isPopupVisible ? "xmark.circle" :*/ "info.circle")
                    .foregroundColor(.blue)
            }
        }
    }
}


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
                viewModel.fetchPrayerTimes()
            }
            .onChange(of: nudgeIsOn) { _, _ in
                viewModel.fetchPrayerTimes()
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
                    viewModel.addToNotificationCenterBySeconds(identifier: "test", content: content, sec: 0.1)
                }
                .font(.subheadline)
                .foregroundColor(.gray)
            
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
                    viewModel.addToNotificationCenterBySeconds(identifier: "test", content: content, sec: 0.1)
                }
                .font(.subheadline)
                .foregroundColor(.gray)

        }
        .padding(.horizontal)

    }
}


struct AlarmSettingsView: View {
    
    // Whether or not to show the informational text section
    @State private var isAlarmInfoVisible: Bool = false
    
    // Local state to manage alert presentation
    @State private var isShowingShortcutAlert: Bool = false
    
    // Persisted state (using AppStorage so the values remain between launches)
    @AppStorage("alarmEnabled") private var alarmEnabled: Bool = false
    
    @AppStorage("alarmOffsetMinutes") private var alarmOffsetMinutes: Int = 0
    @AppStorage("alarmIsBefore") private var alarmIsBefore: Bool = true
    @AppStorage("alarmIsFajr") private var alarmIsFajr: Bool = true
    
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
        
        if let url = URL(string: "https://www.icloud.com/shortcuts/0b1164a730044179ad0afa6ff0d2bc4c"){
            return url
        }
        else {
            return nil
        }
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
                    .foregroundColor(.blue)
            }
        }
        ) {
            
            if isAlarmInfoVisible {
                alarmInfoView
            }
            
            // Toggle to enable/disable alarm
            HStack {
                Image(systemName: "alarm")
                    .foregroundColor(.gray)
                
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
            
            Text("Tired of manually setting up Fajr alarms everyday? This feature lets you define rules once which will dynamically create daily Fajr alarms for you.")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack {
                Image(systemName: "1.circle")
                Text("Click here to add the iOS shortcut")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .underline()
                    .onTapGesture {
                        if let shortcutURL {
                            UIApplication.shared.open(shortcutURL)
                        }
                    }
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
        }
    }
}
