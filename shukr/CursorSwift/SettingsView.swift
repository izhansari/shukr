import SwiftUI

struct QiblaSettings {
    @AppStorage("qibla_sensitivity") static var alignmentThreshold: Double = 3.5
    
    // Optional: Add min/max bounds for the sensitivity
    static let minThreshold: Double = 1.0  // More precise
    static let maxThreshold: Double = 10.0 // More forgiving
}

struct SettingsView: View {
    @ObservedObject var viewModel: PrayerViewModel
    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 2
    @AppStorage("qibla_sensitivity") private var qiblaSensitivity: Double = 3.5
    @State private var refreshID = UUID()
    
    let prayersOld = [
        PrayerModel(
            prayerName: "FAJR",
            startTimeDate: Date().addingTimeInterval(-3800),
            endTimeDate: Date().addingTimeInterval(-2600)
        ),
        PrayerModel(
            prayerName: "ZUHR",
            startTimeDate: Date().addingTimeInterval(-60),
            endTimeDate: Date().addingTimeInterval(30)
        ),
        PrayerModel(
            prayerName: "ASR",
            startTimeDate: Date().addingTimeInterval(30),
            endTimeDate: Date().addingTimeInterval(200)
        ),
        PrayerModel(
            prayerName: "MAGHRIB",
            startTimeDate: Date().addingTimeInterval(200),
            endTimeDate: Date().addingTimeInterval(260)
        ),
        PrayerModel(
            prayerName: "ISHA",
            startTimeDate: Date().addingTimeInterval(260),
            endTimeDate: Date().addingTimeInterval(300)
        )
    ]
    let prayers = [
        PrayerModel(
            prayerName: "FAJR",
            startTimeDate: todayAt(hour: 6, minute: 23),
            endTimeDate: todayAt(hour: 7, minute: 34)
        ),
        PrayerModel(
            prayerName: "ZUHR",
            startTimeDate: todayAt(hour: 13, minute: 6),
            endTimeDate: todayAt(hour: 16, minute: 56)
        ),
        PrayerModel(
            prayerName: "ASR",
            startTimeDate: todayAt(hour: 16, minute: 56),
            endTimeDate: todayAt(hour: 18, minute: 37)
        ),
        PrayerModel(
            prayerName: "MAGHRIB",
            startTimeDate: todayAt(hour: 18, minute: 37),
            endTimeDate: todayAt(hour: 19, minute: 48)
        ),
        PrayerModel(
            prayerName: "ISHA",
            startTimeDate: todayAt(hour: 19, minute: 48),
            endTimeDate: todayAt(hour: 23, minute: 59)
        )
    ]
    
    let calculationMethods = [
        (1, "University of Islamic Sciences, Karachi"),
        (2, "Islamic Society of North America"),
        (3, "Muslim World League"),
        (4, "Umm Al-Qura University, Makkah"),
        (5, "Egyptian General Authority of Survey"),
        (7, "Institute of Geophysics, University of Tehran"),
        (8, "Gulf Region"),
        (9, "Kuwait"),
        (10, "Qatar"),
        (11, "Majlis Ugama Islam Singapura, Singapore"),
        (12, "Union Organization islamic de France"),
        (13, "Diyanet İşleri Başkanlığı, Turkey"),
        (14, "Spiritual Administration of Muslims of Russia")
    ]
    
    let schools = [
        (0, "Shafi'i"),
        (1, "Hanafi")
    ]
    
    var body: some View {
        Form {
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
                Button("Fetch and Print City") {
                    viewModel.fetchAndPrintCity()
                }
            }
            
            Section(header: Text("API Information")) {
                VStack(alignment: .leading) {
                    Text("Last API Call URL:")
                    Link(destination: URL(string: viewModel.lastApiCallUrl) ?? URL(string: "https://example.com")!) {
                        Text(viewModel.lastApiCallUrl)
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(3)
                    }
                }
            }
            
            Section(header: Text("Calculation Method")) {
                Picker("Method", selection: $viewModel.calculationMethod) {
                    ForEach(calculationMethods, id: \.0) { method in
                        Text(method.1).tag(method.0)
                    }
                }
                .onChange(of: viewModel.calculationMethod) { _, new in
                    viewModel.fetchPrayerTimes()
                }
            }
            
            Section(header: Text("Juristic School (for Asr)")) {
                Picker("School", selection: $viewModel.school) {
                    ForEach(schools, id: \.0) { school in
                        Text(school.1).tag(school.0)
                    }
                }
                .onChange(of: viewModel.school) { _, new in
                    viewModel.fetchPrayerTimes()
                }
            }
            
            Section(header: Text("My Dev Stuff")) {
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
            
            HStack{
                NavigationLink(destination: TodayPrayerView(prayers: prayers)) {
                    Text("Prayers V1")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            HStack{
                NavigationLink(destination:  MeccaCompass()) {
                    Text("Qibla V1")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Section(header: Text("Appearance")) {
                Picker("Ring Style", selection: $selectedRingStyle) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                }
                .pickerStyle(.segmented)
                
                // Add Qibla sensitivity slider
                VStack(alignment: .leading) {
                    Text("Qibla Sensitivity: \(qiblaSensitivity, specifier: "%.1f")°")
                    Slider(value: $qiblaSensitivity,
                           in: QiblaSettings.minThreshold...QiblaSettings.maxThreshold,
                           step: 0.5)
                    Text("Lower value = More precise")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Preview of the selected style
                HStack {
                    Spacer()
                    // You might want to create a simplified preview here
                    Text("Style \(selectedRingStyle)")
                        .foregroundColor(.gray)
                    Spacer()
                }
            }
        }
        .navigationTitle("Settings")
        .id(refreshID)
        .onAppear {
            // Force a refresh when the view appears
            refreshID = UUID()
        }
    }
}
