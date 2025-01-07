import SwiftUI
import QuartzCore
// Add this line
import Foundation  // QiblaSettings will be automatically available since it's in your project

class DisplayLink: ObservableObject {
    private var displayLink: CADisplayLink?
    private var callback: ((Date) -> Void)?
    
    func start(callback: @escaping (Date) -> Void) {
        self.callback = callback
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    @objc private func update(displayLink: CADisplayLink) {
        callback?(Date())
    }
}

// Add this struct at the top level
struct PrayerArc {
    let startProgress: Double
    let endProgress: Double
}


struct PulseCircleView: View {
    @EnvironmentObject var sharedState: SharedStateClass

    let prayer: PrayerModel
//    let toggleCompletion: () -> Void
    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 9
    
    @State private var showTimeUntilText: Bool = true
    @State private var showEndTime: Bool = true  // Add this line
    @State private var showQiblaMap: Bool = false
    @State private var isAnimating = false
    @State private var currentTime = Date()
    @Environment(\.colorScheme) var colorScheme
    @State private var timer: Timer?
    @State private var textTrigger = false  // to control the toggle text in the middle
    
    // Replace Timer.publish with DisplayLink
    @StateObject private var displayLink = DisplayLink()
    
    // Add LocationManager
    @StateObject private var locationManager = LocationManager()
    private let meccaLatitude = 21.4225
    private let meccaLongitude = 39.8262

    
    // Timer for updating currentTime
    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var isCurrentPrayer: Bool {
        let now = currentTime
        let isCurrent = now >= prayer.startTime && now < prayer.endTime
        return isCurrent
    }
    
    private var isUpcomingPrayer: Bool {
        currentTime < prayer.startTime
    }
    
    private var progress: Double {
        if isUpcomingPrayer { return 0 }
        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
        let elapsed = currentTime.timeIntervalSince(prayer.startTime)
        return 1 - min(max(elapsed / totalDuration, 0), 1)  // Inverted for countdown
    }
    
    private var progressZone: Int {
        if progress > 0.5 { return 3 }      // Green zone
        else if progress > 0.25 { return 2 } // Yellow zone
        else if progress > 0 { return 1 }    // Red zone
        else { return 0 }                    // No zone (upcoming)
    }
    
    private var pulseRate: Double {
        if progress > 0.5 { return 3 }
        else if progress > 0.25 { return 2 }
        else { return 1 }
    }
    
    private var progressColor: Color {
        if progress > 0.5 { return .green }
        else if progress > 0.25 { return .yellow }
        else if progress > 0 { return .red }
        else if isUpcomingPrayer {return Color(.secondarySystemBackground)/*.white*/}
        else {return .gray}
    }
    
    private func startPulseAnimation() {
        if isPraying {return}
        // First, clean up existing timer
        timer?.invalidate()
        timer = nil
        
        // Only start animation for current prayer
        if isCurrentPrayer {
            
            // Create new timer
            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
                triggerPulse()
//                if !sharedState.showingOtherPages { triggerPulse() }
            }
        }
    }
    
    private func triggerPulse() {
        isAnimating = false
        if !sharedState.showingOtherPages{
            triggerSomeVibration(type: .medium)
        }
        
        withAnimation(.easeOut(duration: pulseRate)) {
            isAnimating = true
        }
    }
    
    private var timeLeftString: String {
        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
        return formatTimeInterval(timeLeft) + " left"
    }
    
    private var timeUntilStartString: String {
        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
        return "in " + formatTimeInterval(timeUntilStart)
    }
    
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
    
    private func iconName(for prayerName: String) -> String {
        switch prayerName.lowercased() {
        case "fajr":
            return "sunrise.fill"
        case "dhuhr":
            return "sun.max.fill"
        case "asr":
            return "sun.haze.fill"
        case "maghrib":
            return "sunset.fill"
        default:
            return "moon.stars.fill"
        }
    }
    
    private var isMissedPrayer: Bool {
        currentTime >= prayer.endTime && !prayer.isCompleted
    }
    
    
    private func calculateQiblaDirection() -> Double {
        guard let userLocation = locationManager.location else { return 0 }
        
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLong = userLocation.coordinate.longitude * .pi / 180
        let meccaLat = meccaLatitude * .pi / 180
        let meccaLong = meccaLongitude * .pi / 180
        
        let y = sin(meccaLong - userLong)
        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
        
        var qiblaDirection = atan2(y, x) * 180 / .pi
        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
        
        let returnVal = qiblaDirection - locationManager.compassHeading
        
        return returnVal
    }
    
    // Add these state variables
    @State private var isPraying: Bool = false
    @State private var prayerStartTime: Date?
    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0
    
    // Add this computed property for formatting the ongoing prayer duration
    private var recordedPrayerDuration: String {
        guard let startTime = prayerStartTime else { return "00:00" }
        let duration = currentTime.timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    @State private var completedPrayerArcs: [PrayerArc] = []
    
    
    private func handlePrayerTracking() {
        triggerSomeVibration(type: .success)
        
        if !isPraying {
            // Start praying
            isPraying = true
            timer?.invalidate()
            timer = nil
            prayerStartTime = Date()
            // Store start time persistently
            UserDefaults.standard.set(prayerStartTime, forKey: "prayerStartTime_\(prayer.name)")
        } else {
            // Finish praying - save the arc
            let newArc = PrayerArc(
                startProgress: prayerTrackingCurrentProgress,
                endProgress: prayerTrackingStartProgress
            )
            completedPrayerArcs.append(newArc)
            
            isPraying = false
            guard let startTime = prayerStartTime else { return }
            let duration = Date().timeIntervalSince(startTime)
            lastPrayerDuration = duration
            
            // Store the prayer duration
            let key = "prayerDurations_\(prayer.name)"
            var durations = UserDefaults.standard.array(forKey: key) as? [TimeInterval] ?? []
            durations.append(duration)
            UserDefaults.standard.set(durations, forKey: key)
            
            // Clear the start time
            UserDefaults.standard.removeObject(forKey: "prayerStartTime_\(prayer.name)")
            prayerStartTime = nil
        }
    }
    
    private var adjustedProgPerZone: Double {
        // get the current progress
        // get the current color
        // if green, its an interval from 1 to 0.5 (0.5 of space). so progress may be 0.7. so show (0.7-0.5)/(0.5)
        // if yellow, its an interval from 0.5 to 0.25 (0.25 of space). so progress may be 0.4. so show (0.4-0.25)/(0.25)
        // if red, its an interval from 0.25 to 0 (0.25 of space). so progress may be 0.1. so show (0.1-0)/(0.25)
        // so the formula is ( {progress} - {sum of intervals below} ) / ( {space of current interval} )
        
        let greenInterval = (1.0, 0.5)
        let yellowInterval = (0.5, 0.25)
        let redInterval = (0.25, 0.0)
        
        if progress >= greenInterval.1 {
            return (progress - greenInterval.1) / (greenInterval.0 - greenInterval.1)
        } else if progress >= yellowInterval.1 {
            return (progress - yellowInterval.1) / (yellowInterval.0 - yellowInterval.1)
        } else {
            return (progress - redInterval.1) / (redInterval.0 - redInterval.1)
        }
    }
    
    // Add these computed properties to calculate the prayer tracking arc
    private var prayerTrackingStartProgress: Double {
        guard let startTime = prayerStartTime else { return 0 }
        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
        let elapsedAtStart = startTime.timeIntervalSince(prayer.startTime)
        return 1 - min(max(elapsedAtStart / totalDuration, 0), 1)
    }

    private var prayerTrackingCurrentProgress: Double {
        guard isPraying, let startTime = prayerStartTime else { return 0 }
        let totalDuration = prayer.endTime.timeIntervalSince(prayer.startTime)
        let elapsedNow = currentTime.timeIntervalSince(prayer.startTime)
        return 1 - min(max(elapsedNow / totalDuration, 0), 1)
    }
    
    private func chooseRingStyle(style: Int) -> AnyView {
        switch style {
        case 0:
            return AnyView(RingStyle0(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 1:
            return AnyView(RingStyle1(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 2:
            return AnyView(RingStyle2(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 3:
            return AnyView(RingStyle3(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 4:
            return AnyView(RingStyle4(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 5:
            return AnyView(RingStyle5(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 6:
            return AnyView(RingStyle6(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 7:
            return AnyView(RingStyle7(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 8:
            return AnyView(RingStyle8(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        case 9:
            return AnyView(RingStyle9(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        default:
            return AnyView(RingStyle2(
                prayer: prayer,
                progress: progress,
                progressColor: progressColor,
                isCurrentPrayer: isCurrentPrayer,
                isAnimating: isAnimating,
                colorScheme: colorScheme,
                isQiblaAligned: abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
            ).body)
        }
    }

    
    var body: some View {
        ZStack {
            
            chooseRingStyle(style: selectedRingStyle)  // Use selectedRingStyle here
            
            // Inner content
            ZStack {
                
                VStack{
                    
                    HStack {
                        Image(systemName: iconName(for: prayer.name))
                            .foregroundColor(isMissedPrayer ? .gray : .secondary)
                            .font(.title)
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                        Text(prayer.name)
                            .font(.title)
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                            .foregroundStyle(.secondary)

                    }
                    
                    if isPraying {
                        HStack {
                            Image(systemName: "record.circle")
                            Text(recordedPrayerDuration)
                        }
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                    }
                    else if isCurrentPrayer {
                        ExternalToggleText(
                            originalText: "ends \(shortTimePM(prayer.endTime))",
                            toggledText: timeLeftString,
                            externalTrigger: $textTrigger,  // Pass the binding
                            fontDesign: .rounded,
                            fontWeight: .thin,
                            hapticFeedback: true
                        )
                        .foregroundStyle(.secondary)
                    } else if isUpcomingPrayer{
                        ExternalToggleText(
                            originalText: "at \(shortTimePM(prayer.startTime))",
                            toggledText: timeUntilStartString,
                            externalTrigger: $textTrigger,  // Pass the binding
                            fontDesign: .rounded,
                            fontWeight: .thin,
                            hapticFeedback: true
                        )
                        .foregroundStyle(.secondary)
                    }
                    
                    if isMissedPrayer {
                        Text("Missed")
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            
            // Show current prayer arc if praying
            if isPraying {
                Circle()
                    .trim(from: prayerTrackingCurrentProgress, to: prayerTrackingStartProgress)
                    .stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundColor(.white.opacity(0.8))
            }
                
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 200, height: 200)
                .onTapGesture {
                    textTrigger.toggle()  // Toggle the trigger
                }
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { _ in
                            if isCurrentPrayer || isPraying {
                                handlePrayerTracking()
                            }
                        }
                )
            
            ZStack {
                let isAligned = abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold

                Image(systemName: "chevron.up")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.001)) // Make the background circle white for debugging
                            .frame(width: 44, height: 44) // Adjust this size to tweak the tappable area
                    )
                    .opacity(0.5)
                    .offset(y: -70)
                    .rotationEffect(Angle(degrees: isAligned ? 0 : calculateQiblaDirection()))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: isAligned)
                    .onChange(of: isAligned) { _, newIsAligned in
                        if newIsAligned {
                            if !sharedState.showingOtherPages{
                                triggerSomeVibration(type: .heavy)
                            }
                        }
                    }

                    .onTapGesture {
                        showQiblaMap = true
                        sharedState.showingOtherPages = true
                    }
                    // Adding a larger tappable area without extra views
                    .frame(width: 44, height: 44) // Adjust as needed to expand tappable area

                    .fullScreenCover(isPresented: $showQiblaMap) {
                        LocationMapContentView()
                        .onAppear {
                            print("showqiblamap (from qibla arrow): \(showQiblaMap)")
                        }
                    }
            }
            
            
        }

        .onAppear {
            startPulseAnimation()
            // Start DisplayLink
            displayLink.start { newTime in
                withAnimation(.linear(duration: 0.1)) {
                    currentTime = newTime
                }
            }
            locationManager.startUpdating() // Start location updates
            // Check for unfinished prayer session
            if let savedStartTime = UserDefaults.standard.object(forKey: "prayerStartTime_\(prayer.name)") as? Date {
                prayerStartTime = savedStartTime
                isPraying = true
            }
        }
        .onChange(of: progressZone) { _, _ in
            startPulseAnimation()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
            displayLink.stop()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { newTime in
            currentTime = newTime
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

// Simplified preview
struct PulseCircleView_Previews: PreviewProvider {
    static var previews: some View {
        let calendar = Calendar.current
        let now = Date()
        let prayer = PrayerModel(
            name: "Asr",
            startTime: calendar.date(byAdding: .second, value: 10, to: now) ?? now,
            endTime: calendar.date(byAdding: .second, value: 50, to: now) ?? now
        )
        
        PulseCircleView(
            prayer: prayer
//            toggleCompletion: {}
        )
        .environmentObject(SharedStateClass())

//        .background(.black)
    }
}

//extension PrayerModel {
//    func getAverageDuration() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        return durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
//    }
//    
//    func getTotalDurationToday() -> TimeInterval {
//        let durations = UserDefaults.standard.array(forKey: "prayerDurations_\(name)") as? [TimeInterval] ?? []
//        let calendar = Calendar.current
//        return durations.filter { duration in
//            if let date = UserDefaults.standard.object(forKey: "prayerDate_\(name)_\(duration)") as? Date {
//                return calendar.isDateInToday(date)
//            }
//            return false
//        }.reduce(0, +)
//    }
//}

struct CustomArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startAngle = Angle(degrees: -90)
        let endAngle = Angle(degrees: -90 + 360 * progress)

        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        return path
    }
}


















































import SwiftUI
import MapKit

// MARK: - QiblaMapView
struct QiblaMapView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(GlobalLocationManager.self) var globalLocationManager
    @EnvironmentObject var sharedState: SharedStateClass
    
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    ))
    @State private var currentRegion: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var centerCoordinate: CLLocationCoordinate2D = .init(latitude: 0, longitude: 0)
    @State private var meccaInisdeRegion: Bool = true
    @State private var mapHeading: Double = 0
    @State private var animatedRotation: Double = 0
    
    @State private var animationFinish: Bool = false
    
    let meccaCoordinate = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)
    

    var body: some View {
        ZStack {
            // Display a map centered on the user’s current location
                Map(position: $cameraPosition) {
                    UserAnnotation()
                    Annotation("Mecca", coordinate: meccaCoordinate) {
                        Text("🕋") // Displaying Kaaba emoji
                            .font(.largeTitle) // Adjust font size as needed
                            .padding(5)
                            .background(Color.white.opacity(0.8)) // Optional background for visibility
                            .clipShape(Circle())
                    }
                }
                .onMapCameraChange { context in
                    currentRegion = context.region
                    centerCoordinate = context.region.center
                    let latitudeDelta = context.region.span.latitudeDelta
                    let longitudeDelta = context.region.span.longitudeDelta
                    print("lationDelta: \(latitudeDelta), longitudeDelta: \(longitudeDelta)")
                    
                    mapHeading = context.camera.heading
                    
                    // Trigger the qiblaFromMapHeading and coordinateInRegion calculations
                    let _ = qiblaFromMapHeading
                    let _ = coordinateInRegion

                    
                }
                .mapStyle(.hybrid(elevation: .realistic))
                .mapControls{
                    MapUserLocationButton()
                    MapCompass()
                }
                .onAppear {
                    globalLocationManager.startUpdating()
                    startMapAnimation()
                }

            
            VStack {
                withAnimation{
                    CircleWithArrowOverlay(degrees: $animatedRotation)
                        .allowsHitTesting(false)
                        .opacity(animationFinish ? 1 : 0)
                        .opacity(meccaInisdeRegion ? 0 : 1)
                }
            }

            
            // Close button
            VStack {
                HStack {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                        sharedState.showingOtherPages = false
                    }
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(8)
                    .padding()
                                        
                    Spacer()

                }
                Spacer()
            }
        }
    }
    
    func startMapAnimation() {

        //zoom out of mecca
        withAnimation(.bouncy(duration: 1)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: meccaCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
            ))
            print("finished part 2")
        }
        
        // zoom to user location
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let userCoordinate = globalLocationManager.userLocation?.coordinate {
                withAnimation(.bouncy(duration: 1)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: userCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.0001, longitudeDelta: 0.0001)
                    ))
                    print("finished part 3")
                    animationFinish = true
                }
            } else {
                print("User location not available")
                updateCameraPosition()
            }
        }
    }
    
    private var coordinateInRegion: Bool {
        let coordinate = meccaCoordinate
        let region = currentRegion
        let topLeftLatitude = region.center.latitude + (region.span.latitudeDelta / 2.0)
        let topLeftLongitude = region.center.longitude - (region.span.longitudeDelta / 2.0)
        
        let bottomRightLatitude = region.center.latitude - (region.span.latitudeDelta / 2.0)
        let bottomRightLongitude = region.center.longitude + (region.span.longitudeDelta / 2.0)

        let retrunVal = (coordinate.latitude <= topLeftLatitude && coordinate.latitude >= bottomRightLatitude &&
                coordinate.longitude >= topLeftLongitude && coordinate.longitude <= bottomRightLongitude)
        
        withAnimation{
            meccaInisdeRegion = retrunVal
        }
        return retrunVal
        
    }
        
    func updateCameraPosition(retryCount: Int = 0) {
        if let userCoordinate = globalLocationManager.userLocation?.coordinate {
            let userRegion = MKCoordinateRegion(center: userCoordinate, span: MKCoordinateSpan(latitudeDelta: 0.0001, longitudeDelta: 0.0001))
            withAnimation {
                cameraPosition = .region(userRegion)
                animationFinish = true
                print("yodeleeeeeeee")
            }
        } else {
            // If user location is not available, retry after a short delay
            if retryCount < 10 { // Limit the number of retries to avoid infinite loop
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // 500ms delay
                    self.updateCameraPosition(retryCount: retryCount + 1)
                }
            } else {
                print("Failed to get user location after multiple attempts")
            }
        }
    }
    
    // Function to calculate Qibla direction based on the user's location
    private func calculateQiblaDirection(turnableStyle: Bool) -> Double {
        let meccaLatitude = 21.4225
        let meccaLongitude = 39.8262
        guard let userLocation = globalLocationManager.userLocation else { return 0 }
        
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLong = userLocation.coordinate.longitude * .pi / 180
        let meccaLat = meccaLatitude * .pi / 180
        let meccaLong = meccaLongitude * .pi / 180
        
        let y = sin(meccaLong - userLong)
        let x = cos(userLat) * tan(meccaLat) - sin(userLat) * cos(meccaLong - userLong)
        
        var qiblaDirection = atan2(y, x) * 180 / .pi
        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
        if turnableStyle{ return qiblaDirection - globalLocationManager.compassHeading }
        else{ return qiblaDirection }

    }
    
    private var qiblaFromMapHeading: Double {
        let meccaLatitude = 21.4225
        let meccaLongitude = 39.8262

        let centerLat = centerCoordinate.latitude * .pi / 180
        let centerLong = centerCoordinate.longitude * .pi / 180
        let meccaLat = meccaLatitude * .pi / 180
        let meccaLong = meccaLongitude * .pi / 180
        
        let y = sin(meccaLong - centerLong)
        let x = cos(centerLat) * tan(meccaLat) - sin(centerLat) * cos(meccaLong - centerLong)
        
        var qiblaDirection = atan2(y, x) * 180 / .pi
        qiblaDirection = (qiblaDirection + 360).truncatingRemainder(dividingBy: 360)
        let newRotation = qiblaDirection - mapHeading
        withAnimation{
            animatedRotation = newRotation
        }

        
        return newRotation

    }

}


// MARK: - CircleWithArrowOverlay
struct CircleWithArrowOverlay: View {
    @Binding var degrees: Double

    var body: some View {
        ZStack {
            let isAligned = abs(degrees) <= QiblaSettings.alignmentThreshold
            Circle()
                .stroke(lineWidth: 24)
                .frame(width: 200, height: 200)
                .foregroundColor(Color.white)
                .opacity(isAligned ? 1 : 0.5)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)

            Image(systemName: "arrowtriangle.up.fill")
                .resizable()
                .foregroundStyle(isAligned ? .green : .white)
                .frame(width: 20, height: 20)
                .offset(y: -100)
                .rotationEffect(.degrees(degrees/*qiblaFromMapHeading*/))
        }
        .frame(width: 200, height: 200)
    }
}

#Preview{
    QiblaMapView()
        .environment(GlobalLocationManager())
}




// MARK: - My Gloabl Location Manager

import SwiftUI
import CoreLocation

@Observable
class GlobalLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @ObservationIgnored let manager = CLLocationManager()
    var userLocation: CLLocation?
    var isAuthorized = false
    var compassHeading: Double = 0

    
    override init(){
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        startLocationServices()
    }
    
    func startLocationServices(){
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse{
            manager.startUpdatingLocation()
            isAuthorized = true
        } else {
            isAuthorized = false
            manager.requestWhenInUseAuthorization()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            manager.requestLocation()
        case .notDetermined:
            isAuthorized = false
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isAuthorized = false
            print("denied")
        default:
            isAuthorized = true
            startLocationServices()
            
        }
    }
        
    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        print(error.localizedDescription)
    }
    
    func startUpdating() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        compassHeading = newHeading.magneticHeading
    }
}
