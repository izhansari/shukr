import SwiftUI

struct QiblaSettings {
    @AppStorage("qibla_sensitivity") static var alignmentThreshold: Double = 3.5
    
    // Optional: Add min/max bounds for the sensitivity
    static let minThreshold: Double = 1.0  // More precise
    static let maxThreshold: Double = 10.0 // More forgiving
}

struct SettingsView: View {
    @EnvironmentObject var viewModel: PrayerViewModel
    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 2
    @AppStorage("qibla_sensitivity") private var qiblaSensitivity: Double = 3.5
    @State private var refreshID = UUID()
    
    @AppStorage("calculationMethod") var calculationMethod: Int = 4
    @AppStorage("school") var school: Int = 0

    @State private var localCalculationMethod: Int = 0
    @State private var localSchool: Int = 0

    
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
                Picker("Method", selection: $localCalculationMethod) {
                    ForEach(calculationMethods, id: \.0) { method in
                        Text(method.1).tag(method.0)
                    }
                }
            }
            
            Section(header: Text("Juristic School (for Asr)")) {
                Picker("School", selection: $localSchool) {
                    ForEach(schools, id: \.0) { school in
                        Text(school.1).tag(school.0)
                    }
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
                Toggle("Debug Location", isOn: $viewModel.locationPrints)
//                    .onChange(of: viewModel.locationPrints) { _, new in
//                        viewModel.toggleLocationPrints()
//                    }
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
                    Text("7").tag(7)
                    Text("8").tag(8)
                    Text("9").tag(9)
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
            localCalculationMethod = calculationMethod
            // Force a refresh when the view appears
            refreshID = UUID()
        }
        .onDisappear{
                calculationMethod = localCalculationMethod
                school = localSchool
                viewModel.fetchPrayerTimes()
            
//            viewModel.fetchPrayerTimes()

        }
    }
}
