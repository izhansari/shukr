import SwiftUI
import SwiftData
import UIKit
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    
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
    
    @State private var selectedPrayerToCancelNudges = "Fajr"
    @State private var rotationAngle: Double = 0 // For rotating the symbol
    
    // for the floating message
    @State private var showFloatingMessage = false // State to control visibility
    
    // For minimizing and expanding the devSection
    @State private var showDevStuff = false

    // For choosing the sheet's content when clicking on the sneak peek stuff
    @State private var selectedUpcomingFeature: sneakPeekItem?
    @State private var showFeatureSheet: Bool = false

    // Create an array of sneakPeekItems.
    let upcomingFeatures: [sneakPeekItem] = [
        sneakPeekItem(image: "map", title: "Masjid Map", description: "For those times you're in another city and need to find a mosque, this will come in handy!"),
        sneakPeekItem(image: "lightbulb.max.fill", title: "Hadith Motivator", description: "Sometimes we lose sight of the intention behind our actions and just go through the motions. A daily Hadith page would be a cool way to stay reminded of our purpose in this dunya"),
        sneakPeekItem(image: "fork.knife", title: "Food Finder", description: "Finding food is hard. Finding halal food - even harder. I wanna partner with another organization for this iA (cough cough HalalEatsNC?!)"),
        sneakPeekItem(image: "character.book.closed", title: "Quranic Vocab", description: "Explore and learn common words from the Quran to make it easier to focus during prayer."),
        sneakPeekItem(image: "gift", title: "Sadaqah Links", description: "A list of trustworthy links to help the ummah. Ideally, Apple Pay integration and donation history in app would be nice!"),
        sneakPeekItem(image: "figure.2.left.holdinghands", title: "Muslim Brand Explorer", description: "I love seeing fellow Muslims doing cool things. So let's make a space for discovering & supporting Muslim brands / influencers.")
    ]
    
    // Define a model for each suggestion.
    struct sneakPeekItem: Identifiable {
        let id = UUID()
        let image: String
        let title: String
        let description: String
    }
    
    let coolBrandLinks: [LinkItem] = [
        LinkItem(title: "DoD", subtitle: "Clothing", imageURL: "https://p19-pu-sign-useast8.tiktokcdn-us.com/tos-useast8-avt-0068-tx2/007b5c7aeffcc3fd7ec601d4aedb7a40~tplv-tiktokx-cropcenter:1080:1080.jpeg?dr=9640&refresh_token=25b1007b&x-expires=1742065200&x-signature=JuvqpjsNen2Kg6HKzH4tyABzt4g%3D&t=4d5b0474&ps=13740610&shp=a5d48078&shcp=81f88b70&idc=useast5", url: URL(string: "https://www.instagram.com/deenoverdunya.us")!),
        LinkItem(title: "Dilkash Gajray", subtitle: "Bridal", imageURL: "https://scontent-iad3-1.cdninstagram.com/v/t51.2885-19/475291630_1150609400015701_4344322516214829308_n.jpg?stp=dst-jpg_s320x320_tt6&_nc_ht=scontent-iad3-1.cdninstagram.com&_nc_cat=101&_nc_oc=Q6cZ2AFR2xxAghsyZBtFl8VgJyYRmtoNqGoIGKe-YfwWPlCu-UW4oTMOyHnFmqxtxEtT9R6wYxP0VbMSmyugCvgjpu3B&_nc_ohc=lCsBLE5msEcQ7kNvgE2RxzX&_nc_gid=10ecb374516d49a5b36b500b6f0165c5&edm=AOQ1c0wBAAAA&ccb=7-5&oh=00_AYGiDEE9wHMJ-6eGZniwzmdnb-ercaQ7-NnfRXI27zOwBQ&oe=67D92853&_nc_sid=8b3546", url: URL(string: "https://www.instagram.com/dilkashgajray/")!),
        LinkItem(title: "Nadrah", subtitle: "Clothing", imageURL: "https://cdn.shopify.com/s/files/1/0729/2695/3760/files/About_us_d0764397-3562-4654-aea7-946c12e50987_1024x1024.png?v=1705556031", url: URL(string: "https://www.tiktok.com/@nadrah.nc")!),
        LinkItem(title: "Ali Hida", subtitle: "Influencer", imageURL: "https://scontent-iad3-2.cdninstagram.com/v/t51.2885-19/454593944_2865268120441221_8097741733498839294_n.jpg?stp=dst-jpg_s320x320_tt6&_nc_ht=scontent-iad3-2.cdninstagram.com&_nc_cat=109&_nc_oc=Q6cZ2AHwpE4kUetl7Gc497wkyNvqc_bK6phXMDOx95Wux8IgltUoNc3CZB1Q_GqVNkb5uNTwDRNm4qYf9e9KndVW2dIr&_nc_ohc=nFWa3LhqFQoQ7kNvgEA1t3m&_nc_gid=047fd04209f847caa7b805713890c49d&edm=AOQ1c0wBAAAA&ccb=7-5&oh=00_AYG9zthcKzwptBHhx7Wit8548ghKRdUAnbDcGk0GdldUiw&oe=67D91259&_nc_sid=8b3546", url: URL(string: "https://www.tiktok.com/@hida_feva")!),
        LinkItem(title: "Latieh", subtitle: "Coffee", imageURL: "https://scontent-iad3-2.cdninstagram.com/v/t51.2885-19/482596401_1338600897348126_7182827564811311299_n.jpg?stp=dst-jpg_s320x320_tt6&_nc_ht=scontent-iad3-2.cdninstagram.com&_nc_cat=106&_nc_oc=Q6cZ2AHb8Pk0sjECcu7JwTINW3VQdrEupMfAX3LHkGu4G_7SUWB9apX5VYQWCsUXtAizxiAZ6Uoo-c02uObz_VPyq6fL&_nc_ohc=uFOUE9IrHD0Q7kNvgFUQFOk&_nc_gid=dec115a7c05d4134a9b7acbbea4f8268&edm=AOQ1c0wBAAAA&ccb=7-5&oh=00_AYF89YIkZxi3uje_bmY3-UVQdekIr8nC94rw1XRR_8T6Lg&oe=67D91181&_nc_sid=8b3546", url: URL(string: "https://www.instagram.com/latiehcoffee")!),
        LinkItem(title: "Zachariah Elkordy", subtitle: "Influencer", imageURL: "https://p19-pu-sign-useast8.tiktokcdn-us.com/tos-useast5-avt-0068-tx/7324462037096988714~tplv-tiktokx-cropcenter:1080:1080.jpeg?dr=9640&refresh_token=d98ef622&x-expires=1742065200&x-signature=O1IDoHqY4kSAPtui3Cw70zQS8Go%3D&t=4d5b0474&ps=13740610&shp=a5d48078&shcp=81f88b70&idc=useast5", url: URL(string: "https://www.instagram.com/zachelkordy")!),
        LinkItem(title: "Sohaib Ashraf", subtitle: "YouTuber", imageURL: "https://yt3.googleusercontent.com/gqmOeoEHqNlRn0zATH93p2uYxaJ0BN7o0YFmO9bTxBp9a-3EgnIsYojQPfW13koaTHO8qZFThA=s160-c-k-c0x00ffffff-no-rj", url: URL(string: "https://www.youtube.com/@SohaibAshraf")!)
    ]
    
    struct LinkItem: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let imageURL: String
        let url: URL
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
//                HStack {
//                    Button(action: {
//                        withAnimation(.spring(duration: 0.3)) {
//                            sharedState.navPosition = sharedState.cameFromNavPosition
//                        }
//                    }) {
//                        Image(systemName: "chevron.left") // Standard back arrow
//                            .font(.title2)
//                            .foregroundColor(.primary)
//                    }
//                    
//                    Spacer()
//                    
//                    Text("Settings") // Center title
//                        .font(.headline)
//                    
//                    Spacer()
//                    
////                    Button(action: {
////                        // Placeholder action
////                    }) {
////                        Image(systemName: "gearshape") // Dummy trailing button (optional)
////                            .font(.title2)
////                            .foregroundColor(.primary)
////                    }
//                    ColorModeToggleButton(showFloatingMessage: $showFloatingMessage)
//                }
//                .padding(.horizontal)
                
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
                        
                        Button("Refresh Location") {
                            viewModel.refreshCityAndPrayerTimes()
                            viewModel.fetchPrayerTimes(cameFrom: "SettingsView Refresh Location Button")
                        }
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
                        .onTapGesture {
                            showDevStuff.toggle()
                        }
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
                        
                        // Qibla sensitivity slider
                        VStack(alignment: .leading){
                            HStack{
                                Image(systemName: "location.north.line")
                                Stepper("Qibla Accuracy: ± \(qiblaSensitivity, specifier: "%.1f")°",
                                        value: $qiblaSensitivity,
                                        in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                                        step: 0.5)
                            }
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
                        
                        Button("Suggest Feature") {
                            // Add action for suggesting a feature.
                        }
                    }

                    
                    //MARK: - Dev Stuff
                    if(showDevStuff){
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
                            Picker("Cancel nudges for", selection: $selectedPrayerToCancelNudges) {
                                ForEach(viewModel.orderedPrayerNames, id: \.self) { prayer in
                                    Text(prayer)
                                }
                            }
                            Button("Cancel for \(selectedPrayerToCancelNudges)") {
//                                viewModel.cancelUpcomingNudges(for: selectedPrayerToCancelNudges) //so it cancels... but when we fetch, we put it right back.
//                                selectedPrayerToCancelNudges.canccel //this new function doesnt work with passing in a string. we have to use the prayerObject.
                            }
                        }

                    }
                    
                }
            }
            floatingMessageView(showFloatingMessage: $showFloatingMessage)
        }
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
                
                if feature.image == "figure.2.left.holdinghands" {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(coolBrandLinks) { link in
                            Link(destination: link.url) {
                                HStack (spacing: 10){
                                    AsyncImage(url: URL(string: link.imageURL)) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView() // Show a loading indicator
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 50, height: 50)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        case .failure:
                                            Image(systemName: "xmark.circle.fill") // Show a default error image
                                                .foregroundColor(.red)
                                                .font(.largeTitle)
                                        @unknown default:
                                            EmptyView() // Handle future cases
                                        }
                                    }
                                    VStack(alignment: .leading){
                                        Text(link.title)
                                            .foregroundColor(.primary)
                                        Text(link.subtitle)
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
                Spacer()
            }
                
            .padding()
            .presentationDetents([.height(300), .medium, .large])
            .presentationDragIndicator(.visible)  // shows the grab handle at the top
            }

        }

        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
    
    var messageToShow: String{
        if colorModeToggleNew == 0{
         "Now in Light Mode"
        } else if colorModeToggleNew == 1{
            "Now in Dark Mode"
        } else {
            "Now in Auto Mode"
        }
//        "Now in \(colorModeToggleNew == 0 ? "Light" : colorModeToggleNew == 1 ? "Dark" : "Auto") Mode"
    }

    var body: some View {
        VStack{
            Spacer()
            
            VStack(spacing: 10) {
                Text(messageToShow)
                    .multilineTextAlignment(.center)
            }
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
            .shadow(radius: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary, lineWidth: 2) // Add stroke with primary color
            )
            .opacity(showFloatingMessage ? 1 : 0.0)
            .padding(.bottom)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(1)
            .animation(.easeInOut, value: showFloatingMessage)
        }
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
                    .foregroundColor(.blue)
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
                    .foregroundColor(.blue)
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
                                .foregroundStyle(isEditingAlarm ? .blue : .gray)
                                .font(isEditingAlarm ? .body : .subheadline)
                            Spacer()
                            Image(systemName: isEditingAlarm ? "square.and.arrow.down" : "pencil") // Add the pencil icon here
                                .foregroundStyle(isEditingAlarm ? .blue : .gray) // Match the color with text
                        }
                    }
            }
            
            // Info Block
            if isAlarmInfoVisible {
                alarmInfoView
            }
        }
        .onAppear{
            nextSunriseTime = viewModel.getNextPrayerTime(for: "sunrise")!
            nextFajrTime = viewModel.getNextPrayerTime(for: "fajr")!
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
