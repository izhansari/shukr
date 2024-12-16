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
    
//    @State private var refreshID = UUID()
    
    @AppStorage("calculationMethod") var calculationMethod: Int = 2
    @AppStorage("school") var school: Int = 0

    @State private var isPopupVisible: Bool = false
    @State private var selectedPrayerToCancelNudges = "Fajr"

    
//    @State private var localCalculationMethod: Int = 0
//    @State private var localSchool: Int = 0

    
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
                        Text("City")
                        Spacer()
                        Text(cityName)
                    }
                } else {
                    Text("Fetching city...")
                }
                HStack {
                    Text("Latitude")
                    Spacer()
                    Text(viewModel.latitude)
                }
                HStack {
                    Text("Longitude")
                    Spacer()
                    Text(viewModel.longitude)
                }
                Button("Refresh Location") {
                    viewModel.refreshCityAndPrayerTimes()
                    viewModel.fetchPrayerTimes()
                }
            }
            
            //MARK: - API Information
            //            Section(header: Text("API Information")) {
            //                VStack(alignment: .leading) {
            //                    Text("Last API Call URL:")
            //                    Link(destination: URL(string: viewModel.lastApiCallUrl) ?? URL(string: "https://example.com")!) {
            //                        Text(viewModel.lastApiCallUrl)
            //                            .font(.caption)
            //                            .foregroundColor(.blue)
            //                            .lineLimit(3)
            //                    }
            //                }
            //            }
            
            
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
                Picker("Ring Style", selection: $selectedRingStyle) {
                    ForEach(0..<10) { index in
                        Text("\(index)").tag(index)
                    }
                    
                }
                
                // Qibla sensitivity slider
                VStack(alignment: .leading) {
                    Text("Qibla Sensitivity: \(qiblaSensitivity, specifier: "%.1f")°")
                    Slider(value: $qiblaSensitivity,
                           in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                           step: 0.5)
                    Text("Lower value = More precise")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            //MARK: - Dev Stuff
            Section(header: Text("My Dev Stuff")) {
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
//        .id(refreshID)
//        .onAppear {
//            localCalculationMethod = calculationMethod
//            localSchool = school
            // Force a refresh when the view appears
//            refreshID = UUID()
//        }
        .onDisappear{
//            calculationMethod = localCalculationMethod
//            school = localSchool
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
                    content.subtitle = "\(randPrayerName) Time 🟢"
                    content.body = "Pray by \(shortTimePM(Date()))"
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
                        (subtitle: "\(randPrayerName) At Midpoint 🟡", body: "Did you pray? There's \(timeLeftString(from: Double.random(in: 60...110)*60))"),
                        (subtitle: "\(randPrayerName) Almost Over! 🔴", body: "Did you pray? There's still \(timeLeftString(from: Double.random(in: 20...45)*60))")
                    ]
                        .randomElement()!
                    content.subtitle = randNudge.subtitle
                    content.body = randNudge.body
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
