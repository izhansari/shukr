import SwiftUI
import CoreLocation

struct Prayer: Identifiable {
    let id = UUID()
    let name: String
    var startTime: Date
    var endTime: Date
    var isCompleted: Bool = false
    var prayerStartedAt: Date?  // When user starts praying
    var prayerCompletedAt: Date?  // When user finishes praying
    var duration: TimeInterval?  // Calculated duration
    var timeAtComplete: Date? = nil
    var numberScore: Double? = nil
    var englishScore: String? = nil
}

class PrayerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var prayers: [Prayer] = [] {
        didSet {
            // Notify that prayers have been updated
            self.objectWillChange.send()
            NotificationCenter.default.post(name: .prayersUpdated, object: nil)
        }
    }
    @Published var calculationMethod: Int = 2 // Default to Islamic Society of North America (ISNA)
    @Published var school: Int = 1 // Default to Shafi'i
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var hasValidLocation: Bool = false
    @Published var cityName: String?
    @Published var latitude: String = "N/A"
    @Published var longitude: String = "N/A"
    @Published var lastApiCallUrl: String = "N/A"
    @Published var useTestPrayers: Bool = false  // Add this property
    
    private let locationManager: CLLocationManager
    private let geocoder = CLGeocoder()
    private var lastGeocodeRequestTime: Date?

    override init() {
        locationManager = CLLocationManager()
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            locationAuthorizationStatus = .denied
            hasValidLocation = false
        case .authorizedWhenInUse, .authorizedAlways:
            locationAuthorizationStatus = .authorizedWhenInUse
            if let location = locationManager.location {
                hasValidLocation = true
                fetchPrayerTimes()
                updateCityName(for: location)
            } else {
                hasValidLocation = false
            }
        @unknown default:
            hasValidLocation = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            updateLocation(location)
        }
    }

    private func updateLocation(_ location: CLLocation) {
        hasValidLocation = true
        latitude = String(format: "%.6f", location.coordinate.latitude)
        longitude = String(format: "%.6f", location.coordinate.longitude)

        // Debounce geocoding requests
        let now = Date()
        if let lastRequestTime = lastGeocodeRequestTime, now.timeIntervalSince(lastRequestTime) < 60 {
            // Skip geocoding if the last request was made less than 60 seconds ago
            return
        }

        // Check if the location has changed significantly
        if let lastLocation = locationManager.location, lastLocation.distance(from: location) < 50 {
            // Skip geocoding if the location hasn't changed significantly
            return
        }

        lastGeocodeRequestTime = now
        updateCityName(for: location)
        fetchPrayerTimes()
    }

    private func updateCityName(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Reverse geocoding error: \(error.localizedDescription)")
                    self?.cityName = "Error fetching city"
                    return
                }

                if let placemark = placemarks?.first {
                    let newCityName = placemark.locality ?? placemark.administrativeArea ?? "Unknown"
                    print("Geocoded City: \(newCityName)")
                    self?.cityName = newCityName
                } else {
                    print("No placemark found")
                    self?.cityName = "Unknown"
                }
            }
        }
    }

    func fetchPrayerTimes() {
        guard let location = locationManager.location else {
            print("Location not available")
            return
        }

        // Update latitude and longitude
        self.latitude = String(format: "%.6f", location.coordinate.latitude)
        self.longitude = String(format: "%.6f", location.coordinate.longitude)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        let currentDate = dateFormatter.string(from: Date())

        let urlString = "https://api.aladhan.com/v1/timings/\(currentDate)?latitude=\(location.coordinate.latitude)&longitude=\(location.coordinate.longitude)&method=\(calculationMethod)&school=\(school)"

        // Update lastApiCallUrl
        self.lastApiCallUrl = urlString

        // Print the complete URL to the console
//        print("API URL: \(urlString)")

        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let data = json["data"] as? [String: Any],
                   let timings = data["timings"] as? [String: String] {

                    DispatchQueue.main.async {
                        let now = Date()
                        let calendar = Calendar.current
                        var testPrayers = [
                            Prayer(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -60*60*3, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now),
                            Prayer(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now),
                            Prayer(name: "Asr", startTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now),
                            Prayer(name: "Maghrib", startTime: calendar.date(byAdding: .second, value: 70, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now),
                            Prayer(name: "Isha", startTime: calendar.date(byAdding: .second, value: 95, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 120, to: now) ?? now)
                        ]
                        var actualPrayers = [
                            Prayer(name: "Fajr", startTime: self.parseTime(timings["Fajr"] ?? ""), endTime: self.parseTime(timings["Sunrise"] ?? "")),
                            Prayer(name: "Dhuhr", startTime: self.parseTime(timings["Dhuhr"] ?? ""), endTime: self.parseTime(timings["Asr"] ?? "")),
                            Prayer(name: "Asr", startTime: self.parseTime(timings["Asr"] ?? ""), endTime: self.parseTime(timings["Maghrib"] ?? "")),
                            Prayer(name: "Maghrib", startTime: self.parseTime(timings["Maghrib"] ?? ""), endTime: self.parseTime(timings["Isha"] ?? "")),
                            Prayer(name: "Isha", startTime: self.parseTime(timings["Isha"] ?? ""), endTime: Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date())
                        ]

                        self.prayers = self.useTestPrayers ? testPrayers : actualPrayers
                    }
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
            }
        }.resume()
    }

    private func parseTime(_ timeString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Set the formatter's time zone to the current time zone
        formatter.timeZone = TimeZone.current
        print("\(TimeZone.current)")

        // Parse the time string
        guard let time = formatter.date(from: timeString) else {
            return Date()
        }

        // Get the current calendar
        let calendar = Calendar.current
        let now = Date()

        // Extract hour and minute from the parsed time
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        // Combine the current date with the parsed time
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                             minute: timeComponents.minute ?? 0,
                             second: 0,
                             of: now) ?? now
    }

    func togglePrayerCompletion(for prayer: Prayer) {
        triggerSomeVibration(type: .light)
        if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
            if(prayers[index].startTime <= Date()){
                prayers[index].isCompleted.toggle()
                if prayers[index].isCompleted{
                    setPrayerScoreFor(at: index)
                }else{
                    prayers[index].timeAtComplete = nil
                    prayers[index].numberScore = nil
                    prayers[index].englishScore = nil
                }
            }
        }
    }



    // CLLocationManagerDelegate method
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkLocationAuthorization()
    }

    func requestLocationAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func fetchAndPrintCity() {
        guard let location = locationManager.location else {
            print("Location not available")
            return
        }
        updateCityName(for: location)
    }
    
    func getColorForPrayerScore(_ score: Double?) -> Color {
        guard let score = score else { return .gray }
        
        if score >= 0.50 {
            return .green
        } else if score >= 0.25 {
            return .yellow
        } else if score > 0 {
            return .red
        } else {
            return .gray
        }
    }

    func setPrayerScoreFor(at index: Int) {
        print("setting time at complete as: ", Date())
        prayers[index].timeAtComplete = Date()

        if let completedTime = prayers[index].timeAtComplete {
            let timeLeft = prayers[index].endTime.timeIntervalSince(completedTime)
            let totalInterval = prayers[index].endTime.timeIntervalSince(prayers[index].startTime)
            let score = timeLeft / totalInterval
            prayers[index].numberScore = max(0, min(score, 1))

            if let percentage = prayers[index].numberScore {
                if percentage > 0.50 {
                    prayers[index].englishScore = "Optimal"
                } else if percentage > 0.25 {
                    prayers[index].englishScore = "Good"
                } else if percentage > 0 {
                    prayers[index].englishScore = "Poor"
                } else {
                    prayers[index].englishScore = "Kaza"
                }
            }
        }
    }
}

class SharedStateClass: ObservableObject {
//    @Published var sessionItems: [SessionDataModel] = []
//
//    // You can initialize it with data or fetch data from persistence here
//    init(sessionItems: [SessionDataModel]) {
//        self.sessionItems = sessionItems
//    }
    
    @Published var selectedPage: Int = 0
    @Published var selectedMinutes: Int = 0
    @Published var targetCount: String = ""
    @Published var titleForSession: String = ""
//    @Published var showingOtherPages: Bool = false
}

struct PrayerTimesView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var viewModel = PrayerViewModel()
    
    @State private var relevantPrayerTimer: Timer? = nil
    @State private var timeDisplayTimer: Timer? = nil
    @State private var activeTimerId: UUID? = nil
    @State private var showBottom: Bool = false
    @State private var showTop: Bool = true
    @State private var dragOffset: CGFloat = 0.0
    @State private var showingDuaPage: Bool = false
    @State private var showingHistoryPage: Bool = false
    @State private var showingTasbeehPage: Bool = false


    private func scheduleNextTransition() {
        // Cancel any existing timer to avoid duplicates
        relevantPrayerTimer?.invalidate()
        
        let now = Date()
        print("\n--- Scheduling Check at \(formatTime(now)) ---")
        
        // Debug: Check if prayers array is empty
        print("Number of prayers: \(viewModel.prayers.count)")
        
        guard !viewModel.prayers.isEmpty else {
            print("⚠️ No prayers available yet")
            return
        }
        
        // Find the next transition time from all prayers
        let nextTransition = viewModel.prayers.compactMap { prayer -> Date? in
            if !prayer.isCompleted && prayer.startTime > now {
                // If prayer hasn't started and isn't completed
                print("Found upcoming prayer: \(prayer.name) at \(formatTime(prayer.startTime))")
                return prayer.startTime
            } else if !prayer.isCompleted && prayer.endTime > now {
                // If prayer is ongoing and isn't completed
                print("Found ongoing prayer: \(prayer.name) ending at \(formatTime(prayer.endTime))")
                return prayer.endTime
            }
            print("Skipping \(prayer.name) - completed or past")
            return nil
        }.min()
        
        // If we found a next transition time
        if let nextTime = nextTransition {
            print("Scheduling next transition for: \(formatTime(nextTime))")
            
            relevantPrayerTimer = Timer.scheduledTimer(
                withTimeInterval: nextTime.timeIntervalSinceNow,
                repeats: false
            ) { _ in
                print("\n🔄 Timer fired at \(self.formatTime(Date()))")
                // Force view refresh when timer fires
                withAnimation {
                    self.viewModel.objectWillChange.send()
                }
                // Schedule the next transition
                self.scheduleNextTransition()
            }
        } else {
            print("⚠️ No more transitions to schedule today")
        }
    }
    
    private func calculateResistance(_ translation: CGFloat) -> CGFloat {
        let maxOffset: CGFloat = 100
        let resistance = 15 * log10(abs(translation) + 1)
        return translation < 0 ? -min(resistance, maxOffset) : min(resistance, maxOffset)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                
                Color.white.opacity(0.001)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    dragOffset = calculateResistance(value.translation.height)
                                }
                            }
                            .onEnded { value in
                                handleDragEnd(translation: value.translation.height)
                            }
                    )

                
                ZStack {
                    VStack {
//                        if showTop{
//                            tasbeehView()
//                        }
//                        else{
                            if let relevantPrayer = viewModel.prayers.first(where: {
                                !$0.isCompleted && $0.startTime <= Date() && $0.endTime >= Date()
                            }) ?? viewModel.prayers.first(where: {
                                !$0.isCompleted && $0.startTime > Date()
                            }) ?? viewModel.prayers.first(where: {
                                !$0.isCompleted && $0.endTime < Date()
                            }) {
                                PulseCircleView(prayer: relevantPrayer) {
                                    viewModel.togglePrayerCompletion(for: relevantPrayer)
                                    scheduleNextTransition()
                                }
                                .transition(.opacity)
                            }
                            
                            if showBottom {
                                RoundedRectangle(cornerSize: CGSize(width: 10, height: 10))
                                    .fill(Color.clear)
                                    .frame(width: 320, height: 350)
                            }
//                        }
                        }
                }
                
                Group {
                    if viewModel.hasValidLocation {
                        VStack {
                            ZStack(alignment: .top) {
                                TopBar(viewModel: viewModel, showingDuaPageBool: $showingDuaPage , showingHistoryPageBool: $showingHistoryPage, showingTasbeehPageBool: $showingTasbeehPage)
                            }
                            
                            Spacer()
                            
                            // Expandable List at bottom
                            VStack {
                                if showBottom {
                                    List {
                                        ForEach(viewModel.prayers) { prayer in
                                            if prayer.isCompleted {
                                                CompletedPrayerListItem(prayer: prayer, toggleCompletion: {
                                                    viewModel.togglePrayerCompletion(for: prayer)
                                                    scheduleNextTransition()
                                                }, viewModel: viewModel)
                                            } else if prayer.startTime > Date() {
                                                UpcomingPrayerListItem(prayer: prayer)
                                            } else {
                                                IncompletePrayerListItem(prayer: prayer, toggleCompletion: {
                                                    viewModel.togglePrayerCompletion(for: prayer)
                                                    scheduleNextTransition()
                                                }, viewModel: viewModel)
                                            }
                                        }
                                    }
                                    .scrollDisabled(true)
                                    .shadow(color: .black.opacity(0.1), radius: 10)
                                    .scrollContentBackground(.hidden)
                                    .frame(width: 320, height: 400)
                                    .transition(.move(edge: .bottom))
                                    .gesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if value.translation.height > 0 {
                                                    dragOffset = calculateResistance(value.translation.height)
                                                }
                                            }
                                            .onEnded { value in
                                                handleDragEnd(translation: value.translation.height)
                                            }
                                    )
                                }
                                
                                // Chevron button
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showBottom.toggle()
                                    }
                                }) {
                                    Image(systemName: showBottom ? "chevron.down" : "chevron.up")
                                        .font(.title3)
                                        .foregroundColor(.gray)
                                        .padding(.bottom, 2)
                                        .padding(.top, 10)
                                        .padding(.horizontal, 20)
                                }
                            }
                            .offset(y: dragOffset)
                        }
                        .navigationBarHidden(true)
                    } else if viewModel.locationAuthorizationStatus != .authorizedWhenInUse {
                        VStack {
                            Text("Location Access Required")
                                .font(.headline)
                                .padding()
                            Text("Please allow location access to fetch accurate prayer times.")
                                .multilineTextAlignment(.center)
                                .padding()
                            Button("Allow Location Access") {
                                viewModel.requestLocationAuthorization()
                            }
                            .padding()
                        }
                    } else{
                        ZStack{
                            CircularProgressView(progress: 0)
                            Text("shukr")
                                .font(.headline)
                                .fontWeight(.thin)
                                .fontDesign(.rounded)
                        }
                        
//                        Circle()
//                            .stroke(lineWidth: 24)
//                            .frame(width: 200, height: 200)
//                            .foregroundStyle(progressColor == .white ? progressColor : progressColor.opacity(0.15))
                    }
                }
                
                if(showingDuaPage){
                    DuaPageView(showingDuaPageBool: $showingDuaPage)
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                }
                if showingHistoryPage{
                    HistoryPageView(showingHistoryPageBool: $showingHistoryPage)
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                }
                if showingTasbeehPage {
                    tasbeehView()
                    .transition(.blurReplace.animation(.easeInOut(duration: 0.4)))
                        .zIndex(1) // Ensure it appears above other content
                }
            }
            .onAppear {
//                sharedState.showingOtherPages = false
                
                if !viewModel.prayers.isEmpty { scheduleNextTransition() }
                NotificationCenter.default.addObserver(
                    forName: .prayersUpdated,
                    object: nil,
                    queue: .main
                ) { _ in
                    scheduleNextTransition()
                }
            }
            .onChange(of: showingDuaPage || showingHistoryPage || showingTasbeehPage){_, new in
//                sharedState.showingOtherPages = new
            }
            .onDisappear {
                relevantPrayerTimer?.invalidate()
                relevantPrayerTimer = nil
                NotificationCenter.default.removeObserver(self)
                timeDisplayTimer?.invalidate()
                timeDisplayTimer = nil
//                print("--------------hey i dis")
            }
        }
        .navigationBarBackButtonHidden()
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: date)
    }
    
    private func handleDragEnd(translation: CGFloat) {
        let threshold: CGFloat = 30
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if translation < -threshold && !showBottom {
                showBottom = true
            } else if translation > threshold && showBottom {
                showBottom = false
            }
            dragOffset = 0
        }
    }
}

struct ContentView3_Previews: PreviewProvider {
    static var previews: some View {
        PrayerTimesView()
            .environmentObject(SharedStateClass()) // Inject the environment object here
    }
}

// Add notification name
extension Notification.Name {
    static let prayersUpdated = Notification.Name("prayersUpdated")
}

// Add these helper functions
private func formatTimeNoSeconds(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

// Updated timeUntilStart function
private func timeUntilStart(_ startTime: Date) -> String {
    let interval = startTime.timeIntervalSince(Date())
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    let seconds = Int(interval) % 60

    if hours > 0 {
        return "in \(hours)h \(minutes)m"
    } else if minutes > 0 {
        return "in \(minutes)m"
    } else {
        return "in \(seconds)s"
    }
}

private var listItemPadding: CGFloat{
    return 1
}

struct IncompletePrayerListItem: View {
    let prayer: Prayer
    let toggleCompletion: () -> Void
    let viewModel: PrayerViewModel

    var body: some View {
        HStack {
            Image(systemName: prayer.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
                .opacity(prayer.startTime <= Date() ? 1 : 0.3)
                .frame(width: 30, alignment: .leading)
                .onTapGesture {
                    toggleCompletion()
                }
            VStack(alignment: .leading) {
                Text(prayer.name)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                Text(formatTimeNoSeconds(prayer.startTime))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            ChevronTap()
        }
        .padding(.vertical, listItemPadding)
    }
    
    private var isMissed: Bool {
        !prayer.isCompleted && prayer.endTime < Date()
    }
}

struct UpcomingPrayerListItem: View {
    let prayer: Prayer

    var body: some View {
        HStack {
            Image(systemName: "circle")
                .foregroundColor(.gray.opacity(0.2))
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading) {
                Text(prayer.name)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .fontWeight(.light)
            }
            Spacer()
            ToggleText(originalText: formatTimeNoSeconds(prayer.startTime), toggledText: timeUntilStart(prayer.startTime), font: .subheadline, fontDesign: .rounded, fontWeight: .light, hapticFeedback: true)
                .foregroundColor(.primary)
                .frame(width: 100, alignment: .trailing)

            ChevronTap()
        }
        .padding(.vertical, listItemPadding)
    }
}

struct CompletedPrayerListItem: View {
    let prayer: Prayer
    let toggleCompletion: () -> Void
    let viewModel: PrayerViewModel

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
                .onTapGesture {
                    toggleCompletion()
                }
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading) {
                Text(prayer.name)
                    .font(.headline)
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                if let completedTime = prayer.timeAtComplete {
                    Text("@ \(formatTimeNoSeconds(completedTime))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                if let engScore = prayer.englishScore, let numScore = prayer.numberScore {
                    Text("\(engScore)")
//                    Text("\(Int(numScore * 100))%")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(width: 100, alignment: .trailing)
            ChevronTap()
        }
        .padding(.vertical, listItemPadding)
    }
}

struct ChevronTap: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.gray)
            .onTapGesture {
                triggerSomeVibration(type: .medium)
                print("chevy hit")
            }
    }
}

struct TopBar: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("modeToggle", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var colorModeToggle = false

    let viewModel: PrayerViewModel
    @Binding var showingDuaPageBool: Bool
    @Binding var showingHistoryPageBool: Bool
    @Binding var showingTasbeehPageBool: Bool
    
    @State private var expandButtons: Bool = false
    


    var body: some View {
//        VStack(spacing: 0){
//            HStack(alignment: .center) {
//                
//                Image(systemName: "xmark")
//                    .font(.system(size: 24))
//                    .foregroundColor(.gray.opacity(0.001))
//                    .padding([.top, .leading, .trailing])
//
//                Spacer()
//                
//                if let cityName = viewModel.cityName {
//                    HStack {
//                        Image(systemName: "location.fill")
//                            .foregroundColor(.secondary)
//                        Text(cityName)
//                    }
//                    .font(.caption)
//                    .fontDesign(.rounded)
//                    .fontWeight(.thin)
//                    .padding([.top, .leading, .trailing])
//                } else {
//                    HStack {
//                        Image(systemName: "location.circle")
//                            .foregroundColor(.secondary)
//                        Text("Fetching location...")
//                    }
//                    .font(.caption)
//                    .fontDesign(.rounded)
//                }
//                
//                
//                
//                Spacer()
//                
//                
//                Button(action: {
//                    triggerSomeVibration(type: .light)
//                    withAnimation {
//                        expandButtons.toggle()
//                    }
//                }) {
//                    Image(systemName: "ellipsis.circle")
//                        .font(.system(size: 24))
//                        .foregroundColor(.gray.opacity(!expandButtons ? 0.3 : 1))
//                        .padding([.top, .leading, .trailing])
//                }
//                
//            }
//            .padding(.top, 8)
//            .padding(.bottom, 5)
//
//            HStack{
//                Spacer()
//                VStack (spacing: 0){
//                    if expandButtons{
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                showingTasbeehPageBool = true
//                            }
//                        }) {
//                            Image(systemName: "circle.hexagonpath")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                showingDuaPageBool = true
//                            }
//                        }) {
//                            Image(systemName: "book")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                showingHistoryPageBool = true
//                            }
//                        }) {
//                            Image(systemName: "rectangle.stack")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        Button(action: {
//                            triggerSomeVibration(type: .light)
//                            withAnimation {
//                                colorModeToggle.toggle()
//                            }
//                        }) {
//                            Image(systemName: colorModeToggle ? "moon.fill" : "sun.max.fill")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                        
//                        NavigationLink(destination: SettingsView(viewModel: viewModel)) {
//                            Image(systemName: "gear")
//                                .font(.system(size: 24))
//                                .foregroundColor(.gray)
//                                .padding(.vertical, 5)
//                        }
//                    }
//                }
//                .padding(.trailing)
//                .opacity(0.7)
//            }
//        }
//        .padding(.horizontal)
        ZStack{
            VStack{
                if let cityName = viewModel.cityName {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.secondary)
                        Text(cityName)
                    }
                    .font(.caption)
                    .fontDesign(.rounded)
                    .fontWeight(.thin)
                    .frame(height: 24, alignment: .center)
//                    .background(.blue)

                } else {
                    HStack {
                        Image(systemName: "location.circle")
                            .foregroundColor(.secondary)
                        Text("Fetching location...")
                    }
                    .font(.caption)
                    .fontDesign(.rounded)
                    .frame(height: 24, alignment: .center)
                }
                
                Spacer()
            }
            .padding()
            
            VStack{
                HStack{
                    Spacer()

                        VStack (spacing: 0){
                            
                            Button(action: {
                                triggerSomeVibration(type: .light)
                                withAnimation {
                                    expandButtons.toggle()
                                }
                            }) {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray.opacity(!expandButtons ? 0.3 : 1))
                                    .padding(.bottom, 7)
                            }
                            
                            if expandButtons{
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
                                        showingTasbeehPageBool = true
                                    }
                                }) {
                                    Image(systemName: "circle.hexagonpath")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
                                        showingDuaPageBool = true
                                    }
                                }) {
                                    Image(systemName: "book")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
                                        showingHistoryPageBool = true
                                    }
                                }) {
                                    Image(systemName: "rectangle.stack")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                Button(action: {
                                    triggerSomeVibration(type: .light)
                                    withAnimation {
                                        colorModeToggle.toggle()
                                    }
                                }) {
                                    Image(systemName: colorModeToggle ? "moon.fill" : "sun.max.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                                
                                NavigationLink(destination: SettingsView(viewModel: viewModel)) {
                                    Image(systemName: "gear")
                                        .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                        .padding(.vertical, 7)
                                }
                            }
                        }
//                        .padding(.trailing)
                        .frame(width: 30)
//                        .background(.red)
                        .opacity(0.7)
                    
                    
                }
                Spacer()
            }.padding()
        }
        .preferredColorScheme(colorModeToggle ? .dark : .light)
    }
}

struct BlankCircleCopy: View {
    var body: some View {
        // Main circle (always visible)
        Circle()
            .stroke(lineWidth: 24)
            .frame(width: 200, height: 200)
            .foregroundColor(Color("wheelColor"))
            .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
        // Inner gradient circle
        Circle()
            .stroke(lineWidth: 0.34)
            .frame(width: 175, height: 175)
            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
            .overlay {
                Circle()
                    .stroke(.black.opacity(0.1), lineWidth: 2)
                    .blur(radius: 5)
                    .mask {
                        Circle()
                            .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
    }
}
