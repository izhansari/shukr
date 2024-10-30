//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = []
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 0 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//    
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//    
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//    
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//        
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//        
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//    
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//                
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//    
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//        
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//        
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//        
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//        
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//        
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//            
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//                    
//                    DispatchQueue.main.async {
//                        self.prayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//    
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//        
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//        
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//        
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//        
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//        
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//    
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                }
//            }
//        }
//    }
//    
//    
//    
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//    
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//    
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//        
//        if let completedTime = prayers[index].timeAtComplete {
//            let completedInterval = (completedTime.timeIntervalSince(prayers[index].startTime))
//            let totalInterval = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
//            let score = completedInterval / totalInterval
//            prayers[index].numberScore = (score > 1 ? 1 : score)
//            
//            if let percentage = prayers[index].numberScore {
//                if percentage >= 1 {
//                    prayers[index].englishScore = "Kaza"
//                } else if percentage > 0.75 {
//                    prayers[index].englishScore = "Poor"
//                } else if percentage > 0.50 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0.00 {
//                    prayers[index].englishScore = "Optimal"
//                } else {
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//    
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//                
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//                
//                Spacer()
//                
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//            
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//    
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//    
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//                
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        if let cityName = viewModel.cityName {
//                            Text(cityName)
//                                .font(.headline)
//                                .padding(.top)
//                        } else {
//                            Text("Fetching location...")
//                                .font(.headline)
//                                .padding(.top)
//                        }
//                        
//                        if let relevantPrayer = viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() }) ?? viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime > Date() }) {
//                            PrayerCardView2(prayer: relevantPrayer, currentTime: Date()) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                            }
//                        }
//                        
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        Text("\(formatTime(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(.secondary)
//                                    }
//                                    Spacer()
//                                    if let completedTime = prayer.timeAtComplete, let numScore = prayer.numberScore, let engScore = prayer.englishScore {
//                                        VStack{
//                                            Text(formatTime(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack{
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    Button(action: {
//                                        if Date() >= prayer.startTime {
////                                            print("\(Date() >= prayer.startTime)")
////                                            print("\(Date())")
////                                            print("\(prayer.startTime)")
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                        }
//                                    }) {
//                                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                    }
//                                }
//                            }
//                            
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .navigationTitle("Daily Prayers")
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}





//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = []
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 0 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//    
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//    
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//    
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//        
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//        
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//    
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//                
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//    
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//        
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//        
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//        
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//        
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//        
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//            
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//                    
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//                        
//                        self.prayers = testPrayers
////                        self.prayers = actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//    
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//        
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//        
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//        
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//        
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//        
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//    
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//    
//    
//    
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//    
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//    
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//        
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//            
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//    
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//                
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//                
//                Spacer()
//                
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//            
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//    
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//    
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//                
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        if let cityName = viewModel.cityName {
//                            Text(cityName)
//                                .font(.headline)
//                                .padding(.top)
//                        } else {
//                            Text("Fetching location...")
//                                .font(.headline)
//                                .padding(.top)
//                        }
//                        
//                        if let relevantPrayer = viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() }) ?? viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime > Date() }) {
//                            PrayerCardView2(prayer: relevantPrayer, currentTime: Date()) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                            }
//                        }
//                        
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        Text("\(formatTime(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(.secondary)
//                                    }
//                                    Spacer()
//                                    if let completedTime = prayer.timeAtComplete, let numScore = prayer.numberScore, let engScore = prayer.englishScore {
//                                        VStack{
//                                            Text(formatTime(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack{
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    Button(action: {
//                                        if Date() >= prayer.startTime {
////                                            print("\(Date() >= prayer.startTime)")
////                                            print("\(Date())")
////                                            print("\(prayer.startTime)")
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                        }
//                                    }) {
//                                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                    }
//                                }
//                            }
//                            
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .navigationTitle("Daily Prayers")
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}




// list item now only completable after start time. tapping on upcoming shows time until for a little bit.

//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = []
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 0 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//    
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//    
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//    
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//        
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//        
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//    
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//                
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//    
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//        
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//        
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//        
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//        
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//        
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//            
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//                    
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//                        
//                        self.prayers = testPrayers
////                        self.prayers = actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//    
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//        
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//        
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//        
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//        
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//        
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//    
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//    
//    
//    
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//    
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//    
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//        
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//            
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//    
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//                
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//                
//                Spacer()
//                
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//            
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//    
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//    
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//                
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var showTimeLeft: [UUID: Bool] = [:]
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        if let cityName = viewModel.cityName {
//                            Text(cityName)
//                                .font(.headline)
//                                .padding(.top)
//                        } else {
//                            Text("Fetching location...")
//                                .font(.headline)
//                                .padding(.top)
//                        }
//                        
//                        if let relevantPrayer = viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() }) ?? viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime > Date() }) {
//                            PrayerCardView2(prayer: relevantPrayer, currentTime: Date()) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                            }
//                        }
//                        
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        if showTimeLeft[prayer.id] == true {
//                                            Text(timeLeft(for: prayer))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        } else {
//                                            Text("\(formatTime(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        }
//                                    }
//                                    Spacer()
//                                    if let completedTime = prayer.timeAtComplete, let numScore = prayer.numberScore, let engScore = prayer.englishScore {
//                                        VStack{
//                                            Text(formatTime(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack{
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    if Date() >= prayer.startTime {
//                                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                    }
//                                }
//                                .contentShape(Rectangle())
//                                .onTapGesture {
//                                    if Date() >= prayer.startTime {
//                                        viewModel.togglePrayerCompletion(for: prayer)
//                                    } else {
//                                        showTimeLeft[prayer.id] = true
//                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                            showTimeLeft[prayer.id] = false
//                                        }
//                                    }
//                                }
//                            }
//                            
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .navigationTitle("Daily Prayers")
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func timeLeft(for prayer: Prayer) -> String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(Date())
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "<1m"
//        }
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}




//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = []
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 0 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//    
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//    
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//    
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//        
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//        
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//    
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//                
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//    
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//        
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//        
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//        
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//        
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//        
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//        
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//            
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//                    
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//                        
//                        self.prayers = testPrayers
////                        self.prayers = actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//    
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//        
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//        
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//        
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//        
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//        
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//    
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//    
//    
//    
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//    
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//    
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//        
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//            
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//    
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//                
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//                
//                Spacer()
//                
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//            
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//    
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//    
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//    
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//    
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//    
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//    
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//    
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//    
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//    
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//                
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var showTimeLeft: [UUID: Bool] = [:]
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        if let cityName = viewModel.cityName {
//                            Text(cityName)
//                                .font(.headline)
//                                .padding(.top)
//                        } else {
//                            Text("Fetching location...")
//                                .font(.headline)
//                                .padding(.top)
//                        }
//                        
//                        if let relevantPrayer = viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() }) ?? viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime > Date() }) {
//                            PrayerCardView2(prayer: relevantPrayer, currentTime: Date()) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                            }
//                        }
//                        
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        if showTimeLeft[prayer.id] == true {
//                                            Text(timeLeft(for: prayer))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        } else {
//                                            Text("\(formatTime(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        }
//                                    }
//                                    Spacer()
//                                    if let completedTime = prayer.timeAtComplete, let numScore = prayer.numberScore, let engScore = prayer.englishScore {
//                                        VStack{
//                                            Text(formatTime(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack{
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    if Date() >= prayer.startTime {
//                                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                    }
//                                }
//                                .contentShape(Rectangle())
//                                .onTapGesture {
//                                    if Date() >= prayer.startTime {
//                                        viewModel.togglePrayerCompletion(for: prayer)
//                                    } else {
//                                        showTimeLeft[prayer.id] = true
//                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
//                                            showTimeLeft[prayer.id] = false
//                                        }
//                                    }
//                                }
//                            }
//                            
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .navigationTitle("Daily Prayers")
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//    
//    private func timeLeft(for prayer: Prayer) -> String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(Date())
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//    
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "<1m"
//        }
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//





// i put the pulsecircle in. this is before im working on getting scheduled time updates
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = []
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 0 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = testPrayers
////                        self.prayers = actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        if let cityName = viewModel.cityName {
//                            Text(cityName)
//                                .font(.headline)
//                                .padding(.top)
//                        } else {
//                            Text("Fetching location...")
//                                .font(.headline)
//                                .padding(.top)
//                        }
//
//                        if let relevantPrayer = viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date() }) ?? viewModel.prayers.first(where: { !$0.isCompleted && $0.startTime > Date() }) {
//                            PulseCircleView(prayer: relevantPrayer){ // Green, slow pulse
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                            }
////                            PrayerCardView2(prayer: relevantPrayer, currentTime: Date()) {
////                                viewModel.togglePrayerCompletion(for: relevantPrayer)
////                            }
//                        }
//
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        Text("\(formatTime(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(.secondary)
//                                    }
//                                    Spacer()
//                                    if let completedTime = prayer.timeAtComplete, let numScore = prayer.numberScore, let engScore = prayer.englishScore {
//                                        VStack{
//                                            Text(formatTime(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack{
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    Button(action: {
//                                        if Date() >= prayer.startTime {
////                                            print("\(Date() >= prayer.startTime)")
////                                            print("\(Date())")
////                                            print("\(prayer.startTime)")
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                        }
//                                    }) {
//                                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                    }
//                                }
//                            }
//
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .navigationTitle("Daily Prayers")
//        }
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//


//i think we got the timeline working:
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 0 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = testPrayers
////                        self.prayers = actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//        
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//        
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//        
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//        
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//        
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//            
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        if let cityName = viewModel.cityName {
//                            Text(cityName)
//                                .font(.headline)
//                                .padding(.top)
//                        } else {
//                            Text("Fetching location...")
//                                .font(.headline)
//                                .padding(.top)
//                        }
//                        
//                        // Find and display relevant prayer
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            !$0.isCompleted &&
//                            $0.startTime <= Date() &&
//                            $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted &&
//                            $0.startTime > Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                // Reschedule transitions after prayer completion
//                                scheduleNextTransition()
//                            }
//                        }
//                        
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        Text("\(formatTime(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(.secondary)
//                                    }
//                                    Spacer()
//                                    if let completedTime = prayer.timeAtComplete,
//                                       let numScore = prayer.numberScore,
//                                       let engScore = prayer.englishScore {
//                                        VStack{
//                                            Text(formatTime(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack{
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    Button(action: {
//                                        if Date() >= prayer.startTime {
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                            // Reschedule transitions after prayer completion
//                                            scheduleNextTransition()
//                                        }
//                                    }) {
//                                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                    }
//                                }
//                            }
//                            
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .onAppear {
//                print("View appeared - waiting for prayers to load")
//                // Listen for prayers being updated
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    print("Prayers loaded - scheduling transitions")
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                print("View disappeared - cleaning up")
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                // Remove observer
//                NotificationCenter.default.removeObserver(self)
//            }
//            .navigationTitle("Daily Prayers")
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//


//everything good but jumping on device. heres the version before:
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = testPrayers
////                        self.prayers = actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    // Add a dictionary to track toggle state for each prayer
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil  // Track which timer is currently showing
//    
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//        
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//        
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//        
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//        
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//        
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//            
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//    
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//        
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//        
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//    
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//
//                        
//                        // Find and display relevant prayer
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            // the current prayer window and not complete
//                            !$0.isCompleted &&
//                            $0.startTime <= Date() &&
//                            $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            // upcoming prayer
//                            !$0.isCompleted &&
//                            $0.startTime > Date()
//                        })  ?? viewModel.prayers.first(where: {
//                            // not completed past prayer
//                            !$0.isCompleted &&
//                            $0.endTime < Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                // Reschedule transitions after prayer completion
//                                scheduleNextTransition()
//                            }
//                            .padding(.bottom)
//                        }
//                        
//                        if let cityName = viewModel.cityName {
//                            HStack {
//                                Image(systemName: "location.fill")
//                                    .foregroundColor(.secondary)
//                                Text(cityName)
//                            }
//                            .font(.caption)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .padding(.top)
//                        } else {
//                            HStack {
//                                Image(systemName: "location.circle")
//                                    .foregroundColor(.secondary)
//                                Text("Fetching location...")
//                            }
//                            .font(.headline)
//                            .padding(.top)
//                        }
//                        
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        if prayer.startTime <= Date() {
//                                            Text("\(formatTimeNoSeconds(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        }
//                                    }
//                                    Spacer()
//                                    
//                                    if prayer.startTime > Date() {
//                                        Text(showTimeUntilText[prayer.id, default: false] ?
//                                            timeUntilStart(prayer.startTime) :
//                                            "at \(formatTimeNoSeconds(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(.secondary)
//                                        Button(action: {
//                                            triggerSomeVibration(type: .light)
//                                            showTimeUntilTextTemporarily(for: prayer.id)
//                                        }) {
//                                        }
//                                    }
//                                    
//                                    if let completedTime = prayer.timeAtComplete,
//                                       let numScore = prayer.numberScore,
//                                       let engScore = prayer.englishScore {
//                                        VStack {
//                                            Text(formatTimeNoSeconds(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack {
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//                                    
//                                    // Only show completion button for current or missed prayers
//                                    if prayer.startTime <= Date() {
//                                        Button(action: {
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                            scheduleNextTransition()
//                                        }) {
//                                            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                        }
//                                    }
//                                }
//                                // Make entire row tappable for upcoming prayers
////                                .contentShape(Rectangle())  // Makes the entire row tappable
////                                .onTapGesture {
////                                    if prayer.startTime > Date() {
////                                        triggerSomeVibration(type: .light)
////                                        showTimeUntilTextTemporarily(for: prayer.id)
////                                    }
////                                }
//                            }
//                        }
//                        .shadow(color: .black.opacity(0.1), radius: 10)
//                        .scrollDisabled(true)
//                        .scrollContentBackground(.hidden)
//                        .toolbar {
//                            ToolbarItem(placement: .navigationBarTrailing) {
//                                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                    Image(systemName: "gear")
//                                        .foregroundStyle(.gray)
//                                }
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .onAppear {
//                print("View appeared - waiting for prayers to load")
//                // Schedule transitions for existing prayers immediately
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//                
//                // Listen for future prayer updates
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    print("Prayers loaded - scheduling transitions")
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                print("View disappeared - cleaning up")
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                // Remove observer
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
////            .navigationTitle("Daily Prayers")
//        }
//    }
//    
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//    
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//


// Good! Version right before starting salah tracker
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    // Add a dictionary to track toggle state for each prayer
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil  // Track which timer is currently showing
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//
//
//                        // Find and display relevant prayer
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            // the current prayer window and not complete
//                            !$0.isCompleted &&
//                            $0.startTime <= Date() &&
//                            $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            // upcoming prayer
//                            !$0.isCompleted &&
//                            $0.startTime > Date()
//                        })  ?? viewModel.prayers.first(where: {
//                            // not completed past prayer
//                            !$0.isCompleted &&
//                            $0.endTime < Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                // Reschedule transitions after prayer completion
//                                scheduleNextTransition()
//                            }
//                            .padding(.bottom)
//                        }
//
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        if prayer.startTime <= Date() {
//                                            Text("\(formatTimeNoSeconds(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        }
//                                    }
//                                    Spacer()
//
//                                    if prayer.startTime > Date() {
//                                        Text(showTimeUntilText[prayer.id, default: false] ?
//                                            timeUntilStart(prayer.startTime) :
//                                            "at \(formatTimeNoSeconds(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(showTimeUntilText[prayer.id, default: false] ? .primary : .secondary)
//                                        Button(action: {
//                                            triggerSomeVibration(type: .light)
//                                            showTimeUntilTextTemporarily(for: prayer.id)
//                                        }) {
//                                        }
//                                    }
//
//                                    if let completedTime = prayer.timeAtComplete,
//                                       let numScore = prayer.numberScore,
//                                       let engScore = prayer.englishScore {
//                                        VStack {
//                                            Text(formatTimeNoSeconds(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack {
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//
//                                    // Only show completion button for current or missed prayers
//                                    if prayer.startTime <= Date() {
//                                        Button(action: {
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                            scheduleNextTransition()
//                                        }) {
//                                            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                        }
//                                    }
//                                }
//                                // Make entire row tappable for upcoming prayers
////                                .contentShape(Rectangle())  // Makes the entire row tappable
////                                .onTapGesture {
////                                    if prayer.startTime > Date() {
////                                        triggerSomeVibration(type: .light)
////                                        showTimeUntilTextTemporarily(for: prayer.id)
////                                    }
////                                }
//                            }
//                        }
//                        .shadow(color: .black.opacity(0.1), radius: 10)
//                        .scrollDisabled(true)
//                        .scrollContentBackground(.hidden)
//                        .toolbar {
//                            ToolbarItem(placement: .navigationBarTrailing) {
//                                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                    Image(systemName: "gear")
//                                        .foregroundStyle(.gray)
//                                }
//                            }
//                        }
//                        if let cityName = viewModel.cityName {
//                            HStack {
//                                Image(systemName: "location.fill")
//                                    .foregroundColor(.secondary)
//                                Text(cityName)
//                            }
//                            .font(.caption)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .padding(.top)
//                        } else {
//                            HStack {
//                                Image(systemName: "location.circle")
//                                    .foregroundColor(.secondary)
//                                Text("Fetching location...")
//                            }
//                            .font(.headline)
//                            .padding(.top)
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .onAppear {
//                print("View appeared - waiting for prayers to load")
//                // Schedule transitions for existing prayers immediately
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//
//                // Listen for future prayer updates
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    print("Prayers loaded - scheduling transitions")
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                print("View disappeared - cleaning up")
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                // Remove observer
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
////            .navigationTitle("Daily Prayers")
//        }
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//
//


// cool so tracker works but not saving to the struct or marking as completed. Edge case of tracking while salah ends needs to be accounted for.
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    // Add a dictionary to track toggle state for each prayer
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil  // Track which timer is currently showing
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//
//
//                        // Find and display relevant prayer
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            // the current prayer window and not complete
//                            !$0.isCompleted &&
//                            $0.startTime <= Date() &&
//                            $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            // upcoming prayer
//                            !$0.isCompleted &&
//                            $0.startTime > Date()
//                        })  ?? viewModel.prayers.first(where: {
//                            // not completed past prayer
//                            !$0.isCompleted &&
//                            $0.endTime < Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                // Reschedule transitions after prayer completion
//                                scheduleNextTransition()
//                            }
//                            .padding(.bottom)
//                        }
//
//                        List {
//                            ForEach(viewModel.prayers) { prayer in
//                                HStack {
//                                    VStack(alignment: .leading) {
//                                        Text(prayer.name)
//                                            .font(.headline)
//                                        if prayer.startTime <= Date() {
//                                            Text("\(formatTimeNoSeconds(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                        }
//                                    }
//                                    Spacer()
//
//                                    if prayer.startTime > Date() {
//                                        Text(showTimeUntilText[prayer.id, default: false] ?
//                                            timeUntilStart(prayer.startTime) :
//                                            "at \(formatTimeNoSeconds(prayer.startTime))")
//                                            .font(.subheadline)
//                                            .foregroundColor(showTimeUntilText[prayer.id, default: false] ? .primary : .secondary)
//                                        Button(action: {
//                                            triggerSomeVibration(type: .light)
//                                            showTimeUntilTextTemporarily(for: prayer.id)
//                                        }) {
//                                        }
//                                    }
//
//                                    if let completedTime = prayer.timeAtComplete,
//                                       let numScore = prayer.numberScore,
//                                       let engScore = prayer.englishScore {
//                                        VStack {
//                                            Text(formatTimeNoSeconds(completedTime))
//                                                .font(.subheadline)
//                                                .foregroundColor(.secondary)
//                                            HStack {
//                                                Text("\(engScore)")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                Text("\(Int(numScore*100))%")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                    }
//
//                                    // Only show completion button for current or missed prayers
//                                    if prayer.startTime <= Date() {
//                                        Button(action: {
//                                            viewModel.togglePrayerCompletion(for: prayer)
//                                            scheduleNextTransition()
//                                        }) {
//                                            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                        }
//                                    }
//                                }
//                                // Make entire row tappable for upcoming prayers
////                                .contentShape(Rectangle())  // Makes the entire row tappable
////                                .onTapGesture {
////                                    if prayer.startTime > Date() {
////                                        triggerSomeVibration(type: .light)
////                                        showTimeUntilTextTemporarily(for: prayer.id)
////                                    }
////                                }
//                            }
//                        }
//                        .shadow(color: .black.opacity(0.1), radius: 10)
//                        .scrollDisabled(true)
//                        .scrollContentBackground(.hidden)
//                        .toolbar {
//                            ToolbarItem(placement: .navigationBarTrailing) {
//                                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                    Image(systemName: "gear")
//                                        .foregroundStyle(.gray)
//                                }
//                            }
//                        }
//                        if let cityName = viewModel.cityName {
//                            HStack {
//                                Image(systemName: "location.fill")
//                                    .foregroundColor(.secondary)
//                                Text(cityName)
//                            }
//                            .font(.caption)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .padding(.top)
//                        } else {
//                            HStack {
//                                Image(systemName: "location.circle")
//                                    .foregroundColor(.secondary)
//                                Text("Fetching location...")
//                            }
//                            .font(.headline)
//                            .padding(.top)
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .onAppear {
//                print("View appeared - waiting for prayers to load")
//                // Schedule transitions for existing prayers immediately
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//
//                // Listen for future prayer updates
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    print("Prayers loaded - scheduling transitions")
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                print("View disappeared - cleaning up")
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                // Remove observer
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
////            .navigationTitle("Daily Prayers")
//        }
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//
//
//
//

// okay this one is fully centered with list expandable from bottom. but navbar messing up our flow
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    // Add a dictionary to track toggle state for each prayer
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil  // Track which timer is currently showing
//    @State private var showList: Bool = false
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        // 1. City at the top
//                        if let cityName = viewModel.cityName {
//                            HStack {
//                                Image(systemName: "location.fill")
//                                    .foregroundColor(.secondary)
//                                Text(cityName)
//                            }
//                            .font(.caption)
//                            .fontDesign(.rounded)
//                            .fontWeight(.thin)
//                            .padding(.top)
//                        } else {
//                            HStack {
//                                Image(systemName: "location.circle")
//                                    .foregroundColor(.secondary)
//                                Text("Fetching location...")
//                            }
//                            .font(.headline)
//                            .padding(.top)
//                        }
//                        
//                        Spacer() // Push content apart
//                        
//                        // 2. PulseCircle in the middle
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.startTime > Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.endTime < Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                scheduleNextTransition()
//                            }
//                        }
//                        
//                        Spacer() // Push content apart
//                        
//                        // 3. Expandable List at bottom
//                        // List view that slides up
//                        if showList {
//                            List {
//                                ForEach(viewModel.prayers) { prayer in
//                                    HStack {
//                                        VStack(alignment: .leading) {
//                                            Text(prayer.name)
//                                                .font(.headline)
//                                            if prayer.startTime <= Date() {
//                                                Text("\(formatTimeNoSeconds(prayer.startTime))")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                        Spacer()
//
//                                        if prayer.startTime > Date() {
//                                            Text(showTimeUntilText[prayer.id, default: false] ?
//                                                timeUntilStart(prayer.startTime) :
//                                                "at \(formatTimeNoSeconds(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(showTimeUntilText[prayer.id, default: false] ? .primary : .secondary)
//                                            Button(action: {
//                                                triggerSomeVibration(type: .light)
//                                                showTimeUntilTextTemporarily(for: prayer.id)
//                                            }) {
//                                            }
//                                        }
//
//                                        if let completedTime = prayer.timeAtComplete,
//                                           let numScore = prayer.numberScore,
//                                           let engScore = prayer.englishScore {
//                                            VStack {
//                                                Text(formatTimeNoSeconds(completedTime))
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                HStack {
//                                                    Text("\(engScore)")
//                                                        .font(.subheadline)
//                                                        .foregroundColor(.secondary)
//                                                    Text("\(Int(numScore*100))%")
//                                                        .font(.subheadline)
//                                                        .foregroundColor(.secondary)
//                                                }
//                                            }
//                                        }
//
//                                        // Only show completion button for current or missed prayers
//                                        if prayer.startTime <= Date() {
//                                            Button(action: {
//                                                viewModel.togglePrayerCompletion(for: prayer)
//                                                scheduleNextTransition()
//                                            }) {
//                                                Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                    .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                            }
//                                        }
//                                    }
//                                    // Make entire row tappable for upcoming prayers
////                                        .contentShape(Rectangle())  // Makes the entire row tappable
////                                        .onTapGesture {
////                                            if prayer.startTime > Date() {
////                                                triggerSomeVibration(type: .light)
////                                                showTimeUntilTextTemporarily(for: prayer.id)
////                                            }
////                                        }
//                                }
//                            }
//                            .scrollDisabled(true)
//                            .scrollContentBackground(.hidden)
//                            .frame(height: 300) // Adjust height as needed
//                            .transition(.move(edge: .bottom))
//                        }
//                        VStack {
//                            // Chevron button
//                            Button(action: {
//                                withAnimation {
//                                    // Toggle list visibility
//                                    showList.toggle()
//                                }
//                            }) {
//                                Image(systemName: showList ? "chevron.down" : "chevron.up")
//                                    .font(.title3)
//                                    .foregroundColor(.gray)
//                                    .padding(.bottom, 2)
//                            }
//                            
//                        }
//                    }
//                    .toolbar {
//                        ToolbarItem(placement: .navigationBarTrailing) {
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                                    .foregroundStyle(.gray)
//                            }
//                        }
//                    }
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .onAppear {
//                print("View appeared - waiting for prayers to load")
//                // Schedule transitions for existing prayers immediately
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//
//                // Listen for future prayer updates
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    print("Prayers loaded - scheduling transitions")
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                print("View disappeared - cleaning up")
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                // Remove observer
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
////            .navigationTitle("Daily Prayers")
//        }
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//
//
//
//
//


//this one before adding the swipe gesture
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    // Add a dictionary to track toggle state for each prayer
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil  // Track which timer is currently showing
//    @State private var showList: Bool = false
//    @Environment(\.presentationMode) var presentationMode
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            Group {
//                if viewModel.hasValidLocation {
//                    VStack {
//                        // Custom top bar with all three elements
//                        HStack {
//                            // Left - X mark
//                            Button(action: {
//                                self.presentationMode.wrappedValue.dismiss()
//                            }) {
//                                Image(systemName: "xmark")
//                                    .foregroundStyle(.gray)
//                            }
//                            
//                            Spacer()
//                            
//                            // Center - City name
//                            if let cityName = viewModel.cityName {
//                                HStack {
//                                    Image(systemName: "location.fill")
//                                        .foregroundColor(.secondary)
//                                    Text(cityName)
//                                }
//                                .font(.caption)
//                                .fontDesign(.rounded)
//                                .fontWeight(.thin)
//                            } else {
//                                HStack {
//                                    Image(systemName: "location.circle")
//                                        .foregroundColor(.secondary)
//                                    Text("Fetching location...")
//                                }
//                                .font(.caption)
//                            }
//                            
//                            Spacer()
//                            
//                            // Right - Settings gear
//                            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                Image(systemName: "gear")
//                                    .foregroundStyle(.gray)
//                            }
//                        }
//                        .padding(.horizontal)
//                        .padding(.top, 8)
//                        
//                        // Rest of your content
//                        Spacer()
//                        
//                        // PulseCircle
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.startTime > Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.endTime < Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                scheduleNextTransition()
//                            }
//                        }
//                        
//                        Spacer()
//                        
//                        // 3. Expandable List at bottom
//                        // List view that slides up
//                        if showList {
//                            List {
//                                ForEach(viewModel.prayers) { prayer in
//                                    HStack {
//                                        VStack(alignment: .leading) {
//                                            Text(prayer.name)
//                                                .font(.headline)
//                                            if prayer.startTime <= Date() {
//                                                Text("\(formatTimeNoSeconds(prayer.startTime))")
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                            }
//                                        }
//                                        Spacer()
//
//                                        if prayer.startTime > Date() {
//                                            Text(showTimeUntilText[prayer.id, default: false] ?
//                                                timeUntilStart(prayer.startTime) :
//                                                "at \(formatTimeNoSeconds(prayer.startTime))")
//                                                .font(.subheadline)
//                                                .foregroundColor(showTimeUntilText[prayer.id, default: false] ? .primary : .secondary)
//                                            Button(action: {
//                                                triggerSomeVibration(type: .light)
//                                                showTimeUntilTextTemporarily(for: prayer.id)
//                                            }) {
//                                            }
//                                        }
//
//                                        if let completedTime = prayer.timeAtComplete,
//                                           let numScore = prayer.numberScore,
//                                           let engScore = prayer.englishScore {
//                                            VStack {
//                                                Text(formatTimeNoSeconds(completedTime))
//                                                    .font(.subheadline)
//                                                    .foregroundColor(.secondary)
//                                                HStack {
//                                                    Text("\(engScore)")
//                                                        .font(.subheadline)
//                                                        .foregroundColor(.secondary)
//                                                    Text("\(Int(numScore*100))%")
//                                                        .font(.subheadline)
//                                                        .foregroundColor(.secondary)
//                                                }
//                                            }
//                                        }
//
//                                        // Only show completion button for current or missed prayers
//                                        if prayer.startTime <= Date() {
//                                            Button(action: {
//                                                viewModel.togglePrayerCompletion(for: prayer)
//                                                scheduleNextTransition()
//                                            }) {
//                                                Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                    .foregroundColor(prayer.isCompleted ? .green : .gray)
//                                            }
//                                        }
//                                    }
//                                    // Make entire row tappable for upcoming prayers
////                                        .contentShape(Rectangle())  // Makes the entire row tappable
////                                        .onTapGesture {
////                                            if prayer.startTime > Date() {
////                                                triggerSomeVibration(type: .light)
////                                                showTimeUntilTextTemporarily(for: prayer.id)
////                                            }
////                                        }
//                                }
//                            }
//                            .scrollDisabled(true)
//                            .scrollContentBackground(.hidden)
//                            .frame(height: 400) // Adjust height as needed
//                            .transition(.move(edge: .bottom))
//                        }
//                        VStack {
//                            // Chevron button
//                            Button(action: {
//                                withAnimation {
//                                    // Toggle list visibility
//                                    showList.toggle()
//                                }
//                            }) {
//                                Image(systemName: showList ? "chevron.down" : "chevron.up")
//                                    .font(.title3)
//                                    .foregroundColor(.gray)
//                                    .padding(.bottom, 2)
//                                    .padding(.top, 10)
//                                    .padding(.horizontal, 20)
//                            }
//                            
//                        }
//                    }
//                    .navigationBarHidden(true)  // Hide the navigation bar completely
//                } else {
//                    VStack {
//                        Text("Location Access Required")
//                            .font(.headline)
//                            .padding()
//                        Text("Please allow location access to fetch accurate prayer times.")
//                            .multilineTextAlignment(.center)
//                            .padding()
//                        Button("Allow Location Access") {
//                            viewModel.requestLocationAuthorization()
//                        }
//                        .padding()
//                    }
//                }
//            }
//            .onAppear {
//                print("View appeared - waiting for prayers to load")
//                // Schedule transitions for existing prayers immediately
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//
//                // Listen for future prayer updates
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    print("Prayers loaded - scheduling transitions")
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                print("View disappeared - cleaning up")
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                // Remove observer
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
////            .navigationTitle("Daily Prayers")
//        }
//        .navigationBarBackButtonHidden()
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//
//
//
//
//
//
//


//this one before adding the fixed list width. was kinda wonky before.
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func getColorForPrayerScore(_ score: Double?) -> Color {
//        guard let score = score else { return .gray }
//        
//        if score >= 0.50 {
//            return .green
//        } else if score >= 0.25 {
//            return .yellow
//        } else if score > 0 {
//            return .red
//        } else {
//            return .gray
//        }
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil
//    @State private var showList: Bool = false
//    @Environment(\.presentationMode) var presentationMode
//    @State private var dragOffset: CGFloat = 0.0
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    // Function to calculate resistance
//    private func calculateResistance(_ translation: CGFloat) -> CGFloat {
//        let maxOffset: CGFloat = 100
//        let resistance = 15 * log10(abs(translation) + 1)
//        return translation < 0 ? -min(resistance, maxOffset) : min(resistance, maxOffset)
//    }
//
//    var body: some View {
//        NavigationView {
//            ZStack {
//                Color.white.opacity(0.001)
//                    .gesture(
//                        DragGesture()
//                            .onChanged { value in
//                                if !showList {
//                                    dragOffset = calculateResistance(value.translation.height)
//                                }
//                            }
//                            .onEnded { value in
//                                if !showList {
//                                    handleDragEnd(translation: value.translation.height)
//                                }
//                            }
//                    )
//
//                Group {
//                    if viewModel.hasValidLocation {
//                        VStack {
//                            // Custom top bar
//                            HStack(alignment: .center) {
//                                Button(action: {
//                                    self.presentationMode.wrappedValue.dismiss()
//                                }) {
//                                    Image(systemName: "xmark")
////                                        .foregroundStyle(.gray)
//                                        .font(.system(size: 24))
//                                        .foregroundColor(.gray)
//                                        .padding()
//
//                                }
//                                
//                                Spacer()
//                                
//                                if let cityName = viewModel.cityName {
//                                    HStack {
//                                        Image(systemName: "location.fill")
//                                            .foregroundColor(.secondary)
//                                        Text(cityName)
//                                    }
//                                    .font(.caption)
//                                    .fontDesign(.rounded)
//                                    .fontWeight(.thin)
//                                    .padding()
//                                } else {
//                                    HStack {
//                                        Image(systemName: "location.circle")
//                                            .foregroundColor(.secondary)
//                                        Text("Fetching location...")
//                                    }
//                                    .font(.caption)
//                                    .fontDesign(.rounded)
//                                }
//                                
//                                Spacer()
//                                
//                                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                    Image(systemName: "gear")
//                                        .font(.system(size: 24))
//                                        .foregroundColor(.gray)
//                                        .padding()
//                                }
//                            }
//                            .padding(.horizontal)
//                            .padding(.top, 8)
//                            
//                            Spacer()
//                            
//                            // PulseCircle
//                            if let relevantPrayer = viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
//                            }) ?? viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.startTime > Date()
//                            }) ?? viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.endTime < Date()
//                            }) {
//                                PulseCircleView(prayer: relevantPrayer) {
//                                    viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                    scheduleNextTransition()
//                                }
//                            }
//                            
//                            Spacer()
//                            
//                            // Expandable List at bottom
//                            VStack {
//                                if showList {
//                                    List {
//                                        ForEach(viewModel.prayers) { prayer in
//                                            HStack {                                                    // Completion button
//                                                
//                                                Button(action: {
//                                                    if prayer.startTime <= Date() {
//                                                        viewModel.togglePrayerCompletion(for: prayer)
//                                                        scheduleNextTransition()
//                                                    }
//                                                }) {
//                                                    Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                        .foregroundColor(/*prayer.isCompleted ?*/ viewModel.getColorForPrayerScore(prayer.numberScore)/* : .gray*/)
//                                                        .opacity(prayer.startTime <= Date() ? 1 : 0.2)
//                                                        .background(Color.clear)
//                                                }
//                                                // Left side - Prayer name and start time
//                                                VStack(alignment: .leading) {
//                                                    Text(prayer.name)
//                                                        .font(.headline)
//                                                        .fontDesign(.rounded)
//                                                        .fontWeight(.light)
//                                                    if prayer.startTime <= Date() {
//                                                        Text("\(formatTimeNoSeconds(prayer.startTime))")
//                                                            .font(.subheadline)
//                                                            .fontDesign(.rounded)
//                                                            .foregroundColor(.secondary)
//                                                    }
//                                                }
//                                                
//                                                Spacer()
//
//                                                // Right side - Time info and button
//                                                HStack(spacing: 8) {
//                                                    // Time text (upcoming or completed)
//                                                    Button(action: {
//                                                        triggerSomeVibration(type: .light)
//                                                        showTimeUntilTextTemporarily(for: prayer.id)
//                                                    }) {
//                                                    }
//                                                    Spacer()
//                                                    if prayer.startTime > Date() {
//                                                        Text(showTimeUntilText[prayer.id, default: false] ?
//                                                            timeUntilStart(prayer.startTime) :
//                                                            "\(formatTimeNoSeconds(prayer.startTime))")
//                                                            .font(.subheadline)
//                                                            .fontDesign(.rounded)
//                                                            .fontWeight(.light)
//                                                            .foregroundColor(.primary)
//                                                            .frame(width: 100, alignment: .trailing)  // Fixed width for alignment
////                                                    Button(action: {
////                                                        print("hit the chevy")
////                                                    }) {
////                                                        Image(systemName: "chevron.right")
////                                                            .foregroundColor(.gray)
////                                                            .onTapGesture {
////                                                                print("hit the chevy")
////                                                            }
////                                                    }
//                                                    
//                                                    } else if let completedTime = prayer.timeAtComplete,
//                                                              let numScore = prayer.numberScore,
//                                                              let engScore = prayer.englishScore {
//                                                        VStack(alignment: .trailing) {
//                                                            Text(formatTimeNoSeconds(completedTime))
//                                                            HStack {
//                                                                Text("\(engScore)")
//                                                                Text("\(Int(numScore*100))%")
//                                                            }
//                                                        }
//                                                        .font(.subheadline)
//                                                        .foregroundColor(.secondary)
//                                                        .frame(width: 100, alignment: .trailing)  // Same fixed width
//                                                    }
//                                                    Image(systemName: "chevron.right")
//                                                        .foregroundColor(.gray)
//                                                        .onTapGesture {
//                                                            print("hit the chevy")
//                                                        }
//                                                }
//                                            }
//                                        }
//                                    }
//                                    .scrollDisabled(true)
//                                    .shadow(color: .black.opacity(0.1), radius: 10)
//                                    .scrollContentBackground(.hidden)
//                                    .frame(width: 300, height: 400)
//                                    .transition(.move(edge: .bottom))
//                                    .gesture(
//                                        DragGesture()
//                                            .onChanged { value in
//                                                if value.translation.height > 0 { // Only allow downward drag when list is shown
//                                                    dragOffset = calculateResistance(value.translation.height)
//                                                }
//                                            }
//                                            .onEnded { value in
//                                                handleDragEnd(translation: value.translation.height)
//                                            }
//                                    )
//                                }
//                                
//                                // Chevron button
//                                Button(action: {
//                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                        showList.toggle()
//                                    }
//                                }) {
//                                    Image(systemName: showList ? "chevron.down" : "chevron.up")
//                                        .font(.title3)
//                                        .foregroundColor(.gray)
//                                        .padding(.bottom, 2)
//                                        .padding(.top, 10)
//                                        .padding(.horizontal, 20)
//                                }
//                            }
//                            .offset(y: dragOffset)
//                        }
//                        .navigationBarHidden(true)
//                    } else {
//                        VStack {
//                            Text("Location Access Required")
//                                .font(.headline)
//                                .padding()
//                            Text("Please allow location access to fetch accurate prayer times.")
//                                .multilineTextAlignment(.center)
//                                .padding()
//                            Button("Allow Location Access") {
//                                viewModel.requestLocationAuthorization()
//                            }
//                            .padding()
//                        }
//                    }
//                }
//            }
//            .onAppear {
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
//        }
//        .navigationBarBackButtonHidden()
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//
//    private func handleDragEnd(translation: CGFloat) {
//        let threshold: CGFloat = 30
//        
//        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//            if translation < -threshold && !showList {
//                showList = true
//            } else if translation > threshold && showList {
//                showList = false
//            }
//            dragOffset = 0
//        }
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//




//Now im gonna try and make subviews for the cards
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func getColorForPrayerScore(_ score: Double?) -> Color {
//        guard let score = score else { return .gray }
//        
//        if score >= 0.50 {
//            return .green
//        } else if score >= 0.25 {
//            return .yellow
//        } else if score > 0 {
//            return .red
//        } else {
//            return .gray
//        }
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil
//    @State private var showList: Bool = false
//    @Environment(\.presentationMode) var presentationMode
//    @State private var dragOffset: CGFloat = 0.0
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    // Function to calculate resistance
//    private func calculateResistance(_ translation: CGFloat) -> CGFloat {
//        let maxOffset: CGFloat = 100
//        let resistance = 15 * log10(abs(translation) + 1)
//        return translation < 0 ? -min(resistance, maxOffset) : min(resistance, maxOffset)
//    }
//
//    var body: some View {
//        NavigationView {
//            ZStack {
//                Color.white.opacity(0.001)
//                    .gesture(
//                        DragGesture()
//                            .onChanged { value in
//                                if !showList {
//                                    dragOffset = calculateResistance(value.translation.height)
//                                }
//                            }
//                            .onEnded { value in
//                                if !showList {
//                                    handleDragEnd(translation: value.translation.height)
//                                }
//                            }
//                    )
//
//                Group {
//                    if viewModel.hasValidLocation {
//                        VStack {
//                            // Custom top bar
//                            HStack(alignment: .center) {
//                                Button(action: {
//                                    self.presentationMode.wrappedValue.dismiss()
//                                }) {
//                                    Image(systemName: "xmark")
////                                        .foregroundStyle(.gray)
//                                        .font(.system(size: 24))
//                                        .foregroundColor(.gray)
//                                        .padding()
//
//                                }
//                                
//                                Spacer()
//                                
//                                if let cityName = viewModel.cityName {
//                                    HStack {
//                                        Image(systemName: "location.fill")
//                                            .foregroundColor(.secondary)
//                                        Text(cityName)
//                                    }
//                                    .font(.caption)
//                                    .fontDesign(.rounded)
//                                    .fontWeight(.thin)
//                                    .padding()
//                                } else {
//                                    HStack {
//                                        Image(systemName: "location.circle")
//                                            .foregroundColor(.secondary)
//                                        Text("Fetching location...")
//                                    }
//                                    .font(.caption)
//                                    .fontDesign(.rounded)
//                                }
//                                
//                                Spacer()
//                                
//                                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                                    Image(systemName: "gear")
//                                        .font(.system(size: 24))
//                                        .foregroundColor(.gray)
//                                        .padding()
//                                }
//                            }
//                            .padding(.horizontal)
//                            .padding(.top, 8)
//                            
//                            Spacer()
//                            
//                            // PulseCircle
//                            if let relevantPrayer = viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
//                            }) ?? viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.startTime > Date()
//                            }) ?? viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.endTime < Date()
//                            }) {
//                                PulseCircleView(prayer: relevantPrayer) {
//                                    viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                    scheduleNextTransition()
//                                }
//                            }
//                            
//                            Spacer()
//                            
//                            // Expandable List at bottom
//                            VStack {
//                                if showList {
//                                    List {
//                                        ForEach(viewModel.prayers) { prayer in
//                                            HStack {
//                                                // Completion button
//                                                Button(action: {
//                                                    if prayer.startTime <= Date() {
//                                                        viewModel.togglePrayerCompletion(for: prayer)
//                                                        scheduleNextTransition()
//                                                    }
//                                                }) {
//                                                    Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                                                        .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
//                                                        .opacity(prayer.startTime <= Date() ? 1 : 0.2)
//                                                }
//                                                
//                                                // Left side - Prayer name and start time
//                                                VStack(alignment: .leading) {
//                                                    Text(prayer.name)
//                                                        .font(.headline)
//                                                        .fontDesign(.rounded)
//                                                        .fontWeight(.light)
//                                                    if prayer.startTime <= Date() {
//                                                        Text(prayer.timeAtComplete != nil ? "@\(formatTimeNoSeconds(prayer.timeAtComplete!))" : formatTimeNoSeconds(prayer.startTime))
//                                                            .font(.subheadline)
//                                                            .fontDesign(.rounded)
//                                                            .foregroundColor(.secondary)
//                                                    }
//                                                }
//                                                
//                                                Spacer()
//
//                                                // Right side - Time info
//                                                Button(action: {
//                                                    triggerSomeVibration(type: .light)
//                                                    showTimeUntilTextTemporarily(for: prayer.id)
//                                                }) {
//                                                    if prayer.startTime > Date() {
//                                                        Text(showTimeUntilText[prayer.id, default: false] ?
//                                                            timeUntilStart(prayer.startTime) :
//                                                            "\(formatTimeNoSeconds(prayer.startTime))")
//                                                            .font(.subheadline)
//                                                            .fontDesign(.rounded)
//                                                            .fontWeight(.light)
//                                                            .foregroundColor(.primary)
//                                                            .frame(width: 100, alignment: .trailing)
//                                                    } else if let completedTime = prayer.timeAtComplete,
//                                                              let numScore = prayer.numberScore,
//                                                              let engScore = prayer.englishScore {
//                                                        VStack(alignment: .trailing) {
////                                                            Text(formatTimeNoSeconds(completedTime))
//                                                            Text("\(engScore)")
////                                                            HStack {
//                                                                Text("\(Int(numScore * 100))%")
////                                                                Text("\(Int(numScore * 100))%")
////                                                            }
//                                                        }
//                                                        .font(.subheadline)
//                                                        .foregroundColor(.secondary)
//                                                        .frame(width: 100, alignment: .trailing)
//                                                    }
//                                                }
//                                                
//                                                Image(systemName: "chevron.right")
//                                                    .foregroundColor(.gray)
//                                                    .onTapGesture {
//                                                        print("hit the chevy")
//                                                    }
//                                            }
//                                            .padding(.vertical, 4) // Adjust the padding value as needed
//                                        }
//                                    }
//                                    .scrollDisabled(true)
//                                    .shadow(color: .black.opacity(0.1), radius: 10)
//                                    .scrollContentBackground(.hidden)
//                                    .frame(width: 320, height: 400)
//                                    .transition(.move(edge: .bottom))
//                                    .gesture(
//                                        DragGesture()
//                                            .onChanged { value in
//                                                if value.translation.height > 0 {
//                                                    dragOffset = calculateResistance(value.translation.height)
//                                                }
//                                            }
//                                            .onEnded { value in
//                                                handleDragEnd(translation: value.translation.height)
//                                            }
//                                    )
//                                }
//                                
//                                // Chevron button
//                                Button(action: {
//                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                        showList.toggle()
//                                    }
//                                }) {
//                                    Image(systemName: showList ? "chevron.down" : "chevron.up")
//                                        .font(.title3)
//                                        .foregroundColor(.gray)
//                                        .padding(.bottom, 2)
//                                        .padding(.top, 10)
//                                        .padding(.horizontal, 20)
//                                }
//                            }
//                            .offset(y: dragOffset)
//                        }
//                        .navigationBarHidden(true)
//                    } else {
//                        VStack {
//                            Text("Location Access Required")
//                                .font(.headline)
//                                .padding()
//                            Text("Please allow location access to fetch accurate prayer times.")
//                                .multilineTextAlignment(.center)
//                                .padding()
//                            Button("Allow Location Access") {
//                                viewModel.requestLocationAuthorization()
//                            }
//                            .padding()
//                        }
//                    }
//                }
//            }
//            .onAppear {
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
//        }
//        .navigationBarBackButtonHidden()
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//
//    private func handleDragEnd(translation: CGFloat) {
//        let threshold: CGFloat = 30
//        
//        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//            if translation < -threshold && !showList {
//                showList = true
//            } else if translation > threshold && showList {
//                showList = false
//            }
//            dragOffset = 0
//        }
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//
//
//




// before trying to fix the swipe:
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func getColorForPrayerScore(_ score: Double?) -> Color {
//        guard let score = score else { return .gray }
//        
//        if score >= 0.50 {
//            return .green
//        } else if score >= 0.25 {
//            return .yellow
//        } else if score > 0 {
//            return .red
//        } else {
//            return .gray
//        }
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil
//    @State private var showList: Bool = false
//    @Environment(\.presentationMode) var presentationMode
//    @State private var dragOffset: CGFloat = 0.0
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    // Function to calculate resistance
//    private func calculateResistance(_ translation: CGFloat) -> CGFloat {
//        let maxOffset: CGFloat = 100
//        let resistance = 15 * log10(abs(translation) + 1)
//        return translation < 0 ? -min(resistance, maxOffset) : min(resistance, maxOffset)
//    }
//
//    var body: some View {
//        NavigationView {
//            ZStack {
//                Color.white.opacity(0.001)
//                    .gesture(
//                        DragGesture()
//                            .onChanged { value in
//                                if !showList {
//                                    dragOffset = calculateResistance(value.translation.height)
//                                }
//                            }
//                            .onEnded { value in
//                                if !showList {
//                                    handleDragEnd(translation: value.translation.height)
//                                }
//                            }
//                    )
//
//                Group {
//                    if viewModel.hasValidLocation {
//                        VStack {
//                            // Custom top bar
//                            TopBar(viewModel: viewModel)
//                            
//                            Spacer()
//                            
//                            // PulseCircle
//                            if let relevantPrayer = viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
//                            }) ?? viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.startTime > Date()
//                            }) ?? viewModel.prayers.first(where: {
//                                !$0.isCompleted && $0.endTime < Date()
//                            }) {
//                                PulseCircleView(prayer: relevantPrayer) {
//                                    viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                    scheduleNextTransition()
//                                }
//                            }
//                            
//                            Spacer()
//                            
//                            // Expandable List at bottom
//                            VStack {
//                                if showList {
//                                    List {
//                                        ForEach(viewModel.prayers) { prayer in
//                                            if prayer.isCompleted {
//                                                CompletedPrayerCard(prayer: prayer, toggleCompletion: {
//                                                    viewModel.togglePrayerCompletion(for: prayer)
//                                                    scheduleNextTransition()
//                                                }, viewModel: viewModel)
//                                            } else if prayer.startTime > Date() {
//                                                UpcomingPrayerCard(prayer: prayer, showTimeUntilText: showTimeUntilText[prayer.id, default: false], showTimeUntilTextTemporarily: {
//                                                    triggerSomeVibration(type: .light)
//                                                    showTimeUntilTextTemporarily(for: prayer.id)
//                                                })
//                                            } else {
//                                                IncompletePrayerCard(prayer: prayer, toggleCompletion: {
//                                                    viewModel.togglePrayerCompletion(for: prayer)
//                                                    scheduleNextTransition()
//                                                }, viewModel: viewModel)
//                                            }
//                                        }
////                                        ForEach(viewModel.prayers) { prayer in
////                                            if prayer.isCompleted {
////                                                CompletedPrayerCard(prayer: prayer) {
////                                                    viewModel.togglePrayerCompletion(for: prayer)
////                                                    scheduleNextTransition()
////                                                }
////                                            } else if prayer.startTime > Date() {
////                                                UpcomingPrayerCard(prayer: prayer, showTimeUntilText: showTimeUntilText[prayer.id, default: false]) {
////                                                    triggerSomeVibration(type: .light)
////                                                    showTimeUntilTextTemporarily(for: prayer.id)
////                                                }
////                                            } else {
////                                                IncompletePrayerCard(prayer: prayer) {
////                                                    viewModel.togglePrayerCompletion(for: prayer)
////                                                    scheduleNextTransition()
////                                                }
////                                            }
////                                        }
//                                    }
//                                    .scrollDisabled(true)
//                                    .shadow(color: .black.opacity(0.1), radius: 10)
//                                    .scrollContentBackground(.hidden)
//                                    .frame(width: 320, height: 400)
//                                    .transition(.move(edge: .bottom))
//                                    .gesture(
//                                        DragGesture()
//                                            .onChanged { value in
//                                                if value.translation.height > 0 {
//                                                    dragOffset = calculateResistance(value.translation.height)
//                                                }
//                                            }
//                                            .onEnded { value in
//                                                handleDragEnd(translation: value.translation.height)
//                                            }
//                                    )
//                                }
//                                
//                                // Chevron button
//                                Button(action: {
//                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                        showList.toggle()
//                                    }
//                                }) {
//                                    Image(systemName: showList ? "chevron.down" : "chevron.up")
//                                        .font(.title3)
//                                        .foregroundColor(.gray)
//                                        .padding(.bottom, 2)
//                                        .padding(.top, 10)
//                                        .padding(.horizontal, 20)
//                                }
//                            }
//                            .offset(y: dragOffset)
//                        }
//                        .navigationBarHidden(true)
//                    } else {
//                        VStack {
//                            Text("Location Access Required")
//                                .font(.headline)
//                                .padding()
//                            Text("Please allow location access to fetch accurate prayer times.")
//                                .multilineTextAlignment(.center)
//                                .padding()
//                            Button("Allow Location Access") {
//                                viewModel.requestLocationAuthorization()
//                            }
//                            .padding()
//                        }
//                    }
//                }
//            }
//            .onAppear {
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
//        }
//        .navigationBarBackButtonHidden()
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//
//    private func handleDragEnd(translation: CGFloat) {
//        let threshold: CGFloat = 30
//        
//        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//            if translation < -threshold && !showList {
//                showList = true
//            } else if translation > threshold && showList {
//                showList = false
//            }
//            dragOffset = 0
//        }
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView3()
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//private var listItemPadding: CGFloat{
//    return 4
//}
//
//struct IncompletePrayerCard: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        HStack {
//            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
//                .opacity(prayer.startTime <= Date() ? 1 : 0.2)
//                .onTapGesture {
//                    toggleCompletion()
//                }
//            VStack(alignment: .leading) {
//                Text(prayer.name)
//                    .font(.headline)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//                Text(formatTimeNoSeconds(prayer.startTime))
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//            }
//            Spacer()
//            ChevronTap()
//        }
//        .padding(.vertical, listItemPadding)
//    }
//    
//    private var isMissed: Bool {
//        !prayer.isCompleted && prayer.endTime < Date()
//    }
//}
//
//struct UpcomingPrayerCard: View {
//    let prayer: Prayer
//    let showTimeUntilText: Bool
//    let showTimeUntilTextTemporarily: () -> Void
//
//    var body: some View {
//        HStack {
//            Image(systemName: "circle")
//                .foregroundColor(.gray.opacity(0.3))
//            VStack(alignment: .leading) {
//                Text(prayer.name)
//                    .font(.headline)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//            }
//            Spacer()
//            Text(showTimeUntilText ? timeUntilStart(prayer.startTime) : formatTimeNoSeconds(prayer.startTime))
//                .font(.subheadline)
//                .foregroundColor(.primary)
//                .frame(width: 100, alignment: .trailing)
//                .onTapGesture {
//                    showTimeUntilTextTemporarily()
//                }
//            ChevronTap()
//        }
//        .padding(.vertical, listItemPadding)
//    }
//}
//
//struct CompletedPrayerCard: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        HStack {
//            Image(systemName: "checkmark.circle.fill")
//                .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
//                .onTapGesture {
//                    toggleCompletion()
//                }
//            VStack(alignment: .leading) {
//                Text(prayer.name)
//                    .font(.headline)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//                if let completedTime = prayer.timeAtComplete {
//                    Text("@\(formatTimeNoSeconds(completedTime))")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary)
//                }
//            }
//            Spacer()
//            VStack(alignment: .trailing) {
//                if let engScore = prayer.englishScore, let numScore = prayer.numberScore {
//                    Text("\(engScore)")
//                    Text("\(Int(numScore * 100))%")
//                }
//            }
//            .font(.subheadline)
//            .foregroundColor(.secondary)
//            .frame(width: 100, alignment: .trailing)
//            ChevronTap()
//        }
//        .padding(.vertical, listItemPadding)
//    }
//}
//
//struct ChevronTap: View {
//    var body: some View {
//        Image(systemName: "chevron.right")
//            .foregroundColor(.gray)
//            .onTapGesture {
//                print("chevy hit")
//            }
//    }
//}
//
//struct TopBar: View {
//    @Environment(\.presentationMode) var presentationMode
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        HStack(alignment: .center) {
//            Button(action: {
//                presentationMode.wrappedValue.dismiss()
//            }) {
//                Image(systemName: "xmark")
//                    .font(.system(size: 24))
//                    .foregroundColor(.gray)
//                    .padding()
//            }
//            
//            Spacer()
//            
//            if let cityName = viewModel.cityName {
//                HStack {
//                    Image(systemName: "location.fill")
//                        .foregroundColor(.secondary)
//                    Text(cityName)
//                }
//                .font(.caption)
//                .fontDesign(.rounded)
//                .fontWeight(.thin)
//                .padding()
//            } else {
//                HStack {
//                    Image(systemName: "location.circle")
//                        .foregroundColor(.secondary)
//                    Text("Fetching location...")
//                }
//                .font(.caption)
//                .fontDesign(.rounded)
//            }
//            
//            Spacer()
//            
//            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                Image(systemName: "gear")
//                    .font(.system(size: 24))
//                    .foregroundColor(.gray)
//                    .padding()
//            }
//        }
//        .padding(.horizontal)
//        .padding(.top, 8)
//    }
//}
//
//






//tryna make the animation:
//import SwiftUI
//import CoreLocation
//
//struct Prayer: Identifiable {
//    let id = UUID()
//    let name: String
//    var startTime: Date
//    var endTime: Date
//    var isCompleted: Bool = false
//    var prayerStartedAt: Date?  // When user starts praying
//    var prayerCompletedAt: Date?  // When user finishes praying
//    var duration: TimeInterval?  // Calculated duration
//    var timeAtComplete: Date? = nil
//    var numberScore: Double? = nil
//    var englishScore: String? = nil
//}
//
//class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var prayers: [Prayer] = [] {
//        didSet {
//            // Notify that prayers have been updated
//            self.objectWillChange.send()
//            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
//        }
//    }
//    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
//    @Published var school: Int = 1 // Default to Shafi'i
//    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
//    @Published var hasValidLocation: Bool = false
//    @Published var cityName: String?
//    @Published var latitude: String = "N/A"
//    @Published var longitude: String = "N/A"
//    @Published var lastApiCallUrl: String = "N/A"
//    @Published var useTestPrayers: Bool = false  // Add this property
//
//    private let locationManager: CLLocationManager
//    private let geocoder = CLGeocoder()
//    private var lastGeocodeRequestTime: Date?
//
//    override init() {
//        locationManager = CLLocationManager()
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func checkLocationAuthorization() {
//        switch locationManager.authorizationStatus {
//        case .notDetermined:
//            locationManager.requestWhenInUseAuthorization()
//        case .restricted, .denied:
//            locationAuthorizationStatus = .denied
//            hasValidLocation = false
//        case .authorizedWhenInUse, .authorizedAlways:
//            locationAuthorizationStatus = .authorizedWhenInUse
//            if let location = locationManager.location {
//                hasValidLocation = true
//                fetchPrayerTimes()
//                updateCityName(for: location)
//            } else {
//                hasValidLocation = false
//            }
//        @unknown default:
//            hasValidLocation = false
//        }
//    }
//
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        if let location = locations.last {
//            updateLocation(location)
//        }
//    }
//
//    private func updateLocation(_ location: CLLocation) {
//        hasValidLocation = true
//        latitude = String(format: "%.6f", location.coordinate.latitude)
//        longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        // Debounce geocoding requests
//        let now = Date()
//        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
//            // Skip geocoding if the last request was made less than 60 seconds ago
//            return
//        }
//
//        // Check if the location has changed significantly
//        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
//            // Skip geocoding if the location hasn't changed significantly
//            return
//        }
//
//        lastGeocodeRequestTime = now
//        updateCityName(for: location)
//        fetchPrayerTimes()
//    }
//
//    private func updateCityName(for location: CLLocation) {
//        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
//            DispatchQueue.main.async {
//                if let error = error {
//                    print("Reverse geocoding error: \(error.localizedDescription)")
//                    self?.cityName = "Error fetching city"
//                    return
//                }
//
//                if let placemark = placemarks?.first {
//                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
//                    print("Geocoded City: \(newCityName)")
//                    self?.cityName = newCityName
//                } else {
//                    print("No placemark found")
//                    self?.cityName = "Unknown"
//                }
//            }
//        }
//    }
//
//    func fetchPrayerTimes() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//
//        // Update latitude and longitude
//        self.latitude = String(format: "%.6f", location.coordinate.latitude)
//        self.longitude = String(format: "%.6f", location.coordinate.longitude)
//
//        let dateFormatter = DateFormatter()
//        dateFormatter.dateFormat = "dd-MM-yyyy"
//        let currentDate = dateFormatter.string(from: Date())
//
//        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"
//
//        // Update lastApiCallUrl
//        self.lastApiCallUrl = urlString
//
//        // Print the complete URL to the console
////        print("API URL: \(urlString)")
//
//        guard let url = URL(string: urlString) else {
//            print("Invalid URL")
//            return
//        }
//
//        URLSession.shared.dataTask(with: url) { data, response, error in
//            guard let data = data, error == nil else {
//                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
//                return
//            }
//
//            do {
//                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
//                   let data = json["data"] as? [String: Any],
//                   let timings = data["timings"] as? [String: String] {
//
//                    DispatchQueue.main.async {
//                        let now = Date()
//                        let calendar = Calendar.current
//                        var testPrayers = [
//                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -5, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now),
//                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 15, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
//                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
//                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
//                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
//                        ]
//                        var actualPrayers = [
//                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
//                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
//                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
//                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
//                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
//                        ]
//
//                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
//                    }
//                }
//            } catch {
//                print("Error parsing JSON: \(error.localizedDescription)")
//            }
//        }.resume()
//    }
//
//    private func parseTime(_ timeString: String) -> Date {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "HH:mm"
//
//        // Set the formatter's time zone to the current time zone
//        formatter.timeZone = TimeZone.current
//        print("\(TimeZone.current)")
//
//        // Parse the time string
//        guard let time = formatter.date(from: timeString) else {
//            return Date()
//        }
//
//        // Get the current calendar
//        let calendar = Calendar.current
//        let now = Date()
//
//        // Extract hour and minute from the parsed time
//        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
//
//        // Combine the current date with the parsed time
//        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
//                             minute: timeComponents.minute ?? 0,
//                             second: 0,
//                             of: now) ?? now
//    }
//
//    func togglePrayerCompletion(for prayer: Prayer) {
//        triggerSomeVibration(type: .light)
//        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
//            if(prayers[index].startTime <= Date()){
//                prayers[index].isCompleted.toggle()
//                if prayers[index].isCompleted{
//                    setPrayerScoreFor(at: index)
////                    let numerator = (prayers[index].timeAtComplete!.timeIntervalSince(prayers[index].startTime))
////                    let denominator = (prayers[index].endTime.timeIntervalSince(prayers[index].startTime))
////                    let score = numerator / denominator
////                    prayers[index].score = (score > 1 ? 1 : score)
//                }else{
//                    prayers[index].timeAtComplete = nil
//                    prayers[index].numberScore = nil
//                    prayers[index].englishScore = nil
//                }
//            }
//        }
//    }
//
//
//
//    // CLLocationManagerDelegate method
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        checkLocationAuthorization()
//    }
//
//    func requestLocationAuthorization() {
//        locationManager.requestWhenInUseAuthorization()
//    }
//
//    func fetchAndPrintCity() {
//        guard let location = locationManager.location else {
//            print("Location not available")
//            return
//        }
//        updateCityName(for: location)
//    }
//    
//    func getColorForPrayerScore(_ score: Double?) -> Color {
//        guard let score = score else { return .gray }
//        
//        if score >= 0.50 {
//            return .green
//        } else if score >= 0.25 {
//            return .yellow
//        } else if score > 0 {
//            return .red
//        } else {
//            return .gray
//        }
//    }
//
//    func setPrayerScoreFor(at index: Int) {
//        print("setting time at complete as: ", Date())
//        prayers[index].timeAtComplete = Date()
//
//        if let completedTime = prayers[index].timeAtComplete {
//            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
//            let score = timeLeft / totalInterval
//            prayers[index].numberScore = max(0, min(score, 1))
//
//            if let percentage = prayers[index].numberScore {
//                if percentage > 0.50 {
//                    prayers[index].englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayers[index].englishScore = "Good"
//                } else if percentage > 0 {
//                    prayers[index].englishScore = "Poor"
//                } else {
//                    prayers[index].englishScore = "Kaza"
//                }
//            }
//        }
//    }
//}
//
//struct PrayerCardView2: View {
//    let prayer: Prayer
//    let currentTime: Date
//    let toggleCompletion: () -> Void
//    @State private var showTimeUntilText: Bool = true
//
//    var body: some View {
//        VStack {
//            HStack {
//                Image(systemName: iconName(for: prayer.name))
//                    .font(.title2)
//                    .foregroundColor(.yellow)
//
//                Text(prayer.name)
//                    .font(.title2)
//                    .fontWeight(.bold)
//
//                Spacer()
//
//                if isCurrentPrayer {
//                    Button(action: toggleCompletion) {
//                        Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                            .foregroundColor(prayer.isCompleted ? .green : .gray)
//                    }
//                }
//            }
//
//            if isCurrentPrayer {
//                Text(timeLeftString)
//                    .font(.headline)
//                ProgressBar(progress: progress, color: progressColor)
//                    .padding(.horizontal, 10)
//                    .frame(height: 5)  // Reduced height to make the line thinner
//                HStack {
//                    Text(formatTime(prayer.startTime))
//                        .font(.caption)
//                    Spacer()
//                    Text(formatTime(prayer.endTime))
//                        .font(.caption)
//                }
//            } else if isUpcomingPrayer {
//                Text(showTimeUntilText ? timeUntilStartString : "\(formatTimeWithAMPM(prayer.startTime))")
//                    .font(.headline)
//                    .onTapGesture {
//                        triggerSomeVibration(type: .light)
//                        showTimeUntilText.toggle()
//                    }
//            } else {
//                Text("Kaza")
//                    .font(.headline)
//            }
//        }
//        .padding()
//        .background(Color(uiColor: .systemBackground))
//        .cornerRadius(15)
//        .shadow(radius: 5)
//        .padding(.horizontal)
//    }
//
//    private var isCurrentPrayer: Bool {
//        currentTime >= prayer.startTime && currentTime < prayer.endTime
//    }
//
//    private var isUpcomingPrayer: Bool {
//        currentTime < prayer.startTime
//    }
//
//    private var progress: Double {
//        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
//        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
//        return min(max(elapsed / totalDuration, 0), 1)
//    }
//
//    private var progressColor: Color {
//        switch progress {
//        case ..<0.5:
//            return .green
//        case ..<0.75:
//            return .yellow
//        default:
//            return .red
//        }
//    }
//
//    private var timeLeftString: String {
//        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
//        return formatTimeInterval(timeLeft) + " left"
//    }
//
//    private var timeUntilStartString: String {
//        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//    }
//
//    private func formatTimeInterval(_ interval: TimeInterval) -> String {
//        let hours = Int(interval) / 3600
//        let minutes = (Int(interval) % 3600) / 60
//        let seconds = Int(interval) % 60
//
//        if hours > 0 {
//            return "\(hours)h \(minutes)m"
//        } else if minutes > 0 {
//            return "\(minutes)m"
//        } else {
//            return "\(seconds)s"
//        }
//    }
//
//    // Function to determine icon based on prayer name
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sunset.fill"
//        case "maghrib":
//            return "moon.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//
//    // Function to format time
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm"
//        return formatter.string(from: date)
//    }
//
//    // Function to format time
//    private func formatTimeWithAMPM(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm a"
//        return formatter.string(from: date)
//    }
//}
//
//struct ProgressBar: View {
//    var progress: Double
//    var color: Color
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack(alignment: .leading) {
//                Rectangle().frame(width: geometry.size.width, height: geometry.size.height)
//                    .opacity(0.3)
//                    .foregroundColor(.gray)
//
//                Rectangle().frame(width: min(CGFloat(self.progress) * geometry.size.width, geometry.size.width), height: geometry.size.height)
//                    .foregroundColor(self.color)
//                    .animation(.linear, value: progress)
//            }
//            .cornerRadius(45.0)
//        }
//    }
//}
//
//struct ContentView3: View {
//    @StateObject private var viewModel = PrayerViewModel()
//    @State private var relevantPrayerTimer: Timer? = nil
//    @State private var showTimeUntilText: [UUID: Bool] = [:]
//    @State private var timeDisplayTimer: Timer? = nil
//    @State private var activeTimerId: UUID? = nil
//    @State private var showList: Bool = false
//    @Environment(\.presentationMode) var presentationMode
//    @State private var dragOffset: CGFloat = 0.0
//    @State private var topBarOpacity: Double = 0.0  // Add this line
//    @State private var pulseCircleOpacity: Double = 0.0
//    @State private var otherComponentsOpacity: Double = 0.0
//    
//    @Binding var showingPrayerPage: Bool
//
//    private func scheduleNextTransition() {
//        // Cancel any existing timer to avoid duplicates
//        relevantPrayerTimer?.invalidate()
//
//        let now = Date()
//        print("\n--- Scheduling Check at \(formatTime(now)) ---")
//
//        // Debug: Check if prayers array is empty
//        print("Number of prayers: \(viewModel.prayers.count)")
//
//        guard !viewModel.prayers.isEmpty else {
//            print("⚠️ No prayers available yet")
//            return
//        }
//
//        // Find the next transition time from all prayers
//        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
//            if !prayer.isCompleted && prayer.startTime > now {
//                // If prayer hasn't started and isn't completed
//                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
//                return prayer.startTime
//            } else if !prayer.isCompleted && prayer.endTime > now {
//                // If prayer is ongoing and isn't completed
//                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
//                return prayer.endTime
//            }
//            print("Skipping \(prayer.name) - completed or past")
//            return nil
//        }.min()
//
//        // If we found a next transition time
//        if let nextTime = nextTransition {
//            print("Scheduling next transition for: \(formatTime(nextTime))")
//
//            relevantPrayerTimer = Timer.scheduledTimer(
//                withTimeInterval: nextTime.timeIntervalSinceNow,
//                repeats: false
//            ) { _ in
//                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
//                // Force view refresh when timer fires
//                withAnimation {
//                    self.viewModel.objectWillChange.send()
//                }
//                // Schedule the next transition
//                self.scheduleNextTransition()
//            }
//        } else {
//            print("⚠️ No more transitions to schedule today")
//        }
//    }
//
//    private func showTimeUntilTextTemporarily(for prayerId: UUID) {
//        // Cancel any existing timer
////        timeDisplayTimer?.invalidate()
//
//        // Show the text
//        withAnimation(.easeIn(duration: 0.2)) {
//            showTimeUntilText[prayerId] = true
//        }
//
//        // Schedule to hide it
//        timeDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
//            withAnimation(.easeOut(duration: 0.2)) {
//                showTimeUntilText[prayerId] = false
//            }
//        }
//    }
//
//    // Function to calculate resistance
//    private func calculateResistance(_ translation: CGFloat) -> CGFloat {
//        let maxOffset: CGFloat = 100
//        let resistance = 15 * log10(abs(translation) + 1)
//        return translation < 0 ? -min(resistance, maxOffset) : min(resistance, maxOffset)
//    }
//
//    var body: some View {
//        NavigationView {
//            ZStack {
//                Color.white.opacity(0.001)
//                    .gesture(
//                        DragGesture()
//                            .onChanged { value in
//                                if value.translation.height > 0 {
//                                    dragOffset = calculateResistance(value.translation.height)
//                                }
//                            }
//                            .onEnded { value in
//                                handleDragEnd(translation: value.translation.height)
//                            }
//                    )
//                
//                ZStack {
//                    BlankCircleCopy()
//                    
//                    // PulseCircle
//                    VStack {
//                        
//                        if let relevantPrayer = viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.startTime > Date()
//                        }) ?? viewModel.prayers.first(where: {
//                            !$0.isCompleted && $0.endTime < Date()
//                        }) {
//                            PulseCircleView(prayer: relevantPrayer) {
//                                viewModel.togglePrayerCompletion(for: relevantPrayer)
//                                scheduleNextTransition()
//                            }
//                            .opacity(pulseCircleOpacity)
//                        }
//                        
//                        if showList {
//                            RoundedRectangle(cornerSize: CGSize(width: 10, height: 10))
//                                .fill(Color.clear)
//                                .frame(width: 320, height: 350)
//                        }
//                    }
//                }
//                .onAppear {
//                    withAnimation(.easeIn(duration: 2)) {
//                        pulseCircleOpacity = 1.0
//                    }
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                        withAnimation(.easeIn(duration: 2)) {
//                            otherComponentsOpacity = 1.0
//                        }
//                    }
//                }
//
//                Group {
//                    if viewModel.hasValidLocation {
//                        VStack {
//                            ZStack(alignment: .top) {
//                                TopBar(viewModel: viewModel, dismissAction: {
//                                    triggerSomeVibration(type: .light)
//                                    withAnimation {
//                                        showingPrayerPage = false
//                                    }
//                                })
//                                .opacity(otherComponentsOpacity)
//                            }
//                            
//                            Spacer()
//                            
//                            // Expandable List at bottom
//                            VStack {
//                                if showList {
//                                    List {
//                                        ForEach(viewModel.prayers) { prayer in
//                                            if prayer.isCompleted {
//                                                CompletedPrayerCard(prayer: prayer, toggleCompletion: {
//                                                    viewModel.togglePrayerCompletion(for: prayer)
//                                                    scheduleNextTransition()
//                                                }, viewModel: viewModel)
//                                            } else if prayer.startTime > Date() {
//                                                UpcomingPrayerCard(prayer: prayer, showTimeUntilText: showTimeUntilText[prayer.id, default: false], showTimeUntilTextTemporarily: {
//                                                    triggerSomeVibration(type: .light)
//                                                    showTimeUntilTextTemporarily(for: prayer.id)
//                                                })
//                                            } else {
//                                                IncompletePrayerCard(prayer: prayer, toggleCompletion: {
//                                                    viewModel.togglePrayerCompletion(for: prayer)
//                                                    scheduleNextTransition()
//                                                }, viewModel: viewModel)
//                                            }
//                                        }
//                                    }
//                                    .scrollDisabled(true)
//                                    .shadow(color: .black.opacity(0.1), radius: 10)
//                                    .scrollContentBackground(.hidden)
//                                    .frame(width: 320, height: 400)
//                                    .transition(.move(edge: .bottom))
//                                    .gesture(
//                                        DragGesture()
//                                            .onChanged { value in
//                                                if value.translation.height > 0 {
//                                                    dragOffset = calculateResistance(value.translation.height)
//                                                }
//                                            }
//                                            .onEnded { value in
//                                                handleDragEnd(translation: value.translation.height)
//                                            }
//                                    )
//                                }
//                                
//                                // Chevron button
//                                Button(action: {
//                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//                                        showList.toggle()
//                                    }
//                                }) {
//                                    Image(systemName: showList ? "chevron.down" : "chevron.up")
//                                        .font(.title3)
//                                        .foregroundColor(.gray)
//                                        .padding(.bottom, 2)
//                                        .padding(.top, 10)
//                                        .padding(.horizontal, 20)
//                                }
//                            }
//                            .offset(y: dragOffset)
//                            .opacity(otherComponentsOpacity)
//                        }
//                        .navigationBarHidden(true)
//                    } else {
//                        VStack {
//                            Text("Location Access Required")
//                                .font(.headline)
//                                .padding()
//                            Text("Please allow location access to fetch accurate prayer times.")
//                                .multilineTextAlignment(.center)
//                                .padding()
//                            Button("Allow Location Access") {
//                                viewModel.requestLocationAuthorization()
//                            }
//                            .padding()
//                        }
//                        .opacity(otherComponentsOpacity)
//                    }
//                }
//            }
//            .onAppear {
//                if !viewModel.prayers.isEmpty {
//                    scheduleNextTransition()
//                }
//                NotificationCenter.default.addObserver(
//                    forName: .prayersUpdated,
//                    object: nil,
//                    queue: .main
//                ) { _ in
//                    scheduleNextTransition()
//                }
//            }
//            .onDisappear {
//                relevantPrayerTimer?.invalidate()
//                relevantPrayerTimer = nil
//                NotificationCenter.default.removeObserver(self)
//                timeDisplayTimer?.invalidate()
//                timeDisplayTimer = nil
//            }
//        }
//        .navigationBarBackButtonHidden()
//    }
//
//    private func formatTime(_ date: Date) -> String {
//        let formatter = DateFormatter()
//        formatter.dateFormat = "h:mm:ss a"
//        return formatter.string(from: date)
//    }
//
//    private func handleDragEnd(translation: CGFloat) {
//        let threshold: CGFloat = 30
//        
//        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
//            if translation < -threshold && !showList {
//                showList = true
//            } else if translation > threshold && showList {
//                showList = false
//            }
//            dragOffset = 0
//        }
//    }
//}
//
//struct ContentView3_Previews: PreviewProvider {
//    static var previews: some View {
//        @Previewable @State var showingPrayerPage = true
//        ContentView3(showingPrayerPage: $showingPrayerPage)
//    }
//}
//
//// Add notification name
//extension Notification.Name {
//    static let prayersUpdated = Notification.Name("prayersUpdated")
//}
//
//// Add these helper functions
//private func formatTimeNoSeconds(_ date: Date) -> String {
//    let formatter = DateFormatter()
//    formatter.dateFormat = "h:mm a"
//    return formatter.string(from: date)
//}
//
//// Updated timeUntilStart function
//private func timeUntilStart(_ startTime: Date) -> String {
//    let interval = startTime.timeIntervalSince(Date())
//    let hours = Int(interval) / 3600
//    let minutes = (Int(interval) % 3600) / 60
//    let seconds = Int(interval) % 60
//
//    if hours > 0 {
//        return "in \(hours)h \(minutes)m"
//    } else if minutes > 0 {
//        return "in \(minutes)m"
//    } else {
//        return "in \(seconds)s"
//    }
//}
//
//private var listItemPadding: CGFloat{
//    return 4
//}
//
//struct IncompletePrayerCard: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        HStack {
//            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
//                .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
//                .opacity(prayer.startTime <= Date() ? 1 : 0.2)
//                .onTapGesture {
//                    toggleCompletion()
//                }
//            VStack(alignment: .leading) {
//                Text(prayer.name)
//                    .font(.headline)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//                Text(formatTimeNoSeconds(prayer.startTime))
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//            }
//            Spacer()
//            ChevronTap()
//        }
//        .padding(.vertical, listItemPadding)
//    }
//    
//    private var isMissed: Bool {
//        !prayer.isCompleted && prayer.endTime < Date()
//    }
//}
//
//struct UpcomingPrayerCard: View {
//    let prayer: Prayer
//    let showTimeUntilText: Bool
//    let showTimeUntilTextTemporarily: () -> Void
//
//    var body: some View {
//        HStack {
//            Image(systemName: "circle")
//                .foregroundColor(.gray.opacity(0.3))
//            VStack(alignment: .leading) {
//                Text(prayer.name)
//                    .font(.headline)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//            }
//            Spacer()
//            Text(showTimeUntilText ? timeUntilStart(prayer.startTime) : formatTimeNoSeconds(prayer.startTime))
//                .font(.subheadline)
//                .foregroundColor(.primary)
//                .frame(width: 100, alignment: .trailing)
//                .onTapGesture {
//                    showTimeUntilTextTemporarily()
//                }
//            ChevronTap()
//        }
//        .padding(.vertical, listItemPadding)
//    }
//}
//
//struct CompletedPrayerCard: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        HStack {
//            Image(systemName: "checkmark.circle.fill")
//                .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
//                .onTapGesture {
//                    toggleCompletion()
//                }
//            VStack(alignment: .leading) {
//                Text(prayer.name)
//                    .font(.headline)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//                if let completedTime = prayer.timeAtComplete {
//                    Text("@\(formatTimeNoSeconds(completedTime))")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary)
//                }
//            }
//            Spacer()
//            VStack(alignment: .trailing) {
//                if let engScore = prayer.englishScore, let numScore = prayer.numberScore {
//                    Text("\(engScore)")
//                    Text("\(Int(numScore * 100))%")
//                }
//            }
//            .font(.subheadline)
//            .foregroundColor(.secondary)
//            .frame(width: 100, alignment: .trailing)
//            ChevronTap()
//        }
//        .padding(.vertical, listItemPadding)
//    }
//}
//
//struct ChevronTap: View {
//    var body: some View {
//        Image(systemName: "chevron.right")
//            .foregroundColor(.gray)
//            .onTapGesture {
//                print("chevy hit")
//            }
//    }
//}
//
//struct TopBar: View {
//    @Environment(\.presentationMode) var presentationMode
//    let viewModel: PrayerViewModel
//    let dismissAction: () -> Void
//
//    var body: some View {
//        HStack(alignment: .center) {
//            Button(action: dismissAction) {
//                Image(systemName: "xmark")
//                    .font(.system(size: 24))
//                    .foregroundColor(.gray)
//                    .padding()
//            }
//            
//            Spacer()
//            
//            if let cityName = viewModel.cityName {
//                HStack {
//                    Image(systemName: "location.fill")
//                        .foregroundColor(.secondary)
//                    Text(cityName)
//                }
//                .font(.caption)
//                .fontDesign(.rounded)
//                .fontWeight(.thin)
//                .padding()
//            } else {
//                HStack {
//                    Image(systemName: "location.circle")
//                        .foregroundColor(.secondary)
//                    Text("Fetching location...")
//                }
//                .font(.caption)
//                .fontDesign(.rounded)
//            }
//            
//            Spacer()
//            
//            NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                Image(systemName: "gear")
//                    .font(.system(size: 24))
//                    .foregroundColor(.gray)
//                    .padding()
//            }
//        }
//        .padding(.horizontal)
//        .padding(.top, 8)
//    }
//}
//
//
//struct BlankCircleCopy: View {
//    var body: some View {
//        // Main circle (always visible)
//        Circle()
//            .stroke(lineWidth: 24)
//            .frame(width: 200, height: 200)
//            .foregroundColor(Color("wheelColor"))
//            .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
//        // Inner gradient circle
//        Circle()
//            .stroke(lineWidth: 0.34)
//            .frame(width: 175, height: 175)
//            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
//            .overlay {
//                Circle()
//                    .stroke(.black.opacity(0.1), lineWidth: 2)
//                    .blur(radius: 5)
//                    .mask {
//                        Circle()
//                            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
//                    }
//            }
//    }
//}
//
