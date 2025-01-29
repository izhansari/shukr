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


struct PulseCircleView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.colorScheme) var colorScheme


    let prayer: PrayerModel
//    let toggleCompletion: () -> Void
    @AppStorage("selectedRingStyle") private var selectedRingStyle: Int = 9
    
    @State private var showTimeUntilText: Bool = true
    @State private var showEndTime: Bool = true  // Add this line
//    @State private var showQiblaMap: Bool = false
    @Binding var showQiblaMap: Bool
    @State private var isAnimating = false
    @State private var currentTime = Date()
//    @State private var timer: Timer?
    @State private var textTrigger = false  // to control the toggle text in the middle
//    @State private var showingPulseView: Bool = false
//    @State private var isPraying: Bool = false
//    @State private var prayerStartTime: Date?
////    @State private var completedPrayerArcs: [PrayerArc] = []
//    @AppStorage("lastPrayerDuration") private var lastPrayerDuration: TimeInterval = 0

    
    // Replace Timer.publish with DisplayLink
//    @StateObject private var displayLink = DisplayLink()
    
    // Add LocationManager
    @StateObject private var locationManager = LocationManager()
//    private let meccaLatitude = 21.4225
//    private let meccaLongitude = 39.8262

    
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
        else {return .clear}
    }
    
//    private var showingPulseView: Bool{
//        sharedState.showingPulseView
//    }
    
//    private func startPulseAnimation() {
////        if isPraying {return}
//        // First, clean up existing timer
//        timer?.invalidate()
//        timer = nil
//        
//        // Only start animation for current prayer
//        if isCurrentPrayer {
//            
//            // Create new timer
//            timer = Timer.scheduledTimer(withTimeInterval: pulseRate, repeats: true) { _ in
//                triggerPulse()
////                if !sharedState.showingOtherPages { triggerPulse() }
//            }
//        }
//    }
    
//    private func triggerPulse() {
//        isAnimating = false
//        if sharedState.showingPulseView && (sharedState.navPosition == .bottom || sharedState.navPosition == .main) /*sharedState.showSalahTab*/{
//            triggerSomeVibration(type: .medium)
//        }
//        print("triggerPulse: showing pulseView \(sharedState.showingPulseView) (still calling it)")
//
//        withAnimation(.easeOut(duration: pulseRate)) {
//            isAnimating = true
//        }
//    }
    
    private func checkToTriggerQiblaHaptic(aligned: Bool){
        if aligned {
            if sharedState.showingPulseView/*!sharedState.showingOtherPages*/{
                triggerSomeVibration(type: .heavy)
            }
            print("checkToTriggerQiblaHaptic: showing pulseView \(sharedState.showingPulseView)")

        }
    }
    
    private var timeLeftString: String {
        let timeLeft = prayer.endTime.timeIntervalSince(currentTime)
        return formatTimeInterval(timeLeft) + " left"
    }
    
    private var timeUntilStartString: String {
        let timeUntilStart = prayer.startTime.timeIntervalSince(currentTime)
//        return "in " + formatTimeInterval(timeUntilStart)
//        return inMinSecStyle(from: timeUntilStart)
        return inMinSecStyle2(from: timeUntilStart)
    }
    
//    private func prayerIcon(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sun.haze.fill"
//        case "maghrib":
//            return "sunset.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
    
    private var isMissedPrayer: Bool {
        currentTime >= prayer.endTime && !prayer.isCompleted
    }
    
    
    private func calculateQiblaDirection() -> Double {
        guard let userLocation = locationManager.location else { return 0 }
        let meccaLatitude = 21.4225
        let meccaLongitude = 39.8262
        
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
    
    private var isQiblaAligned: Bool{
        abs(calculateQiblaDirection()) <= QiblaSettings.alignmentThreshold
    }
    
//    private var timeToDisplay: Date {
//        if isCurrentPrayer{ prayer.endTime }
//        else { prayer.startTime }
//    }
//    
//    private var timeStyle: Text.DateStyle{
//        if isCurrentPrayer{ .relative }
//        else { .time }
//    }
    
    private var timeText: Text{
        if isCurrentPrayer{ Text(prayer.endTime, style: textTrigger ? .time : .relative) }
        else if isUpcomingPrayer { Text(prayer.startTime, style: textTrigger ? .relative : .time) }
        else { Text("Missed") }
    }
    
    private func handleTap() {
        triggerSomeVibration(type: .light)
//        timer?.invalidate()
//        withAnimation{ textTrigger.toggle() }
        withAnimation(.easeInOut(duration: 0.2)) { textTrigger.toggle() }
    }

    
    var body: some View {
        ZStack {
            
                

                ZStack{
                    // main circle
                    Circle()
                        .fill(Color(.systemBackground))
                        .stroke(Color(.secondarySystemFill), lineWidth: 12)
                        .frame(width: 200, height: 200)

                    // progress arc
                    Circle()
                        .trim(from: 0, to: 1-progress) // Adjust progress value (0 to 1)
                        .stroke( progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                    

                    // Qibla indicator
                    Circle()
                        .frame(width: 4, height: 4)
                        .offset(y: -100)
                        .foregroundStyle(.primary)
                        .opacity(isQiblaAligned ? 0.5 : 0)
                        .zIndex(1)
                    
                    // Inner content
                    ZStack{
                        VStack{
                            HStack(alignment: .center){
                                Image(systemName: prayerIcon(for: prayer.name))
                                Text(prayer.name)
                                    .fontWeight(.bold)
                            }
                            .font(.title)
                            timeText
                                .foregroundColor(.primary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .onTapGesture {
                    handleTap()
                }
            

            /*
            // main circle
            Circle()
                .fill(Color(.systemBackground))
                .stroke(Color(.secondarySystemFill), lineWidth: 12)
                .frame(width: 200, height: 200)

            // progress arc
            Circle()
                .trim(from: 0, to: 1-progress) // Adjust progress value (0 to 1)
                .stroke( progressColor, style: StrokeStyle(lineWidth: 4, lineCap: .butt)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)
            

            // Qibla indicator
            Circle()
                .frame(width: 4, height: 4)
                .offset(y: -100)
                .foregroundStyle(.primary)
                .opacity(isQiblaAligned ? 0.5 : 0)
                .zIndex(1)
            
            // Inner content
            ZStack{
                VStack{
                    HStack(alignment: .center){
                        Image(systemName: prayerIcon(for: prayer.name))
                        Text(prayer.name)
                            .fontWeight(.bold)
                    }
                    .font(.title)
                    timeText
                        .foregroundColor(.primary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            */
            
            
            /*
            .onChange(of: textTrigger){ _, _ in
                handleTap()
            }
            ZStack {
                
                VStack{
                    
                    HStack {
                        Image(systemName: prayerIcon(for: prayer.name))
                            .foregroundColor(isMissedPrayer ? .gray : .primary/*.secondary*/)
                            .font(.title)
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                        Text(prayer.name)
                            .font(.title)
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                            .foregroundStyle(.primary)/*.foregroundStyle(.secondary)*/
                    }
                    
                    if isCurrentPrayer {
                        ExternalToggleText(
                            originalText: "ends \(shortTimePM(prayer.endTime))",
                            toggledText: timeLeftString,
                            externalTrigger: $textTrigger,  // Pass the binding
                            fontDesign: .rounded,
                            fontWeight: .thin,
                            hapticFeedback: true
                        )
                        .foregroundStyle(.primary)/*.foregroundStyle(.secondary)*/
                    } else if isUpcomingPrayer{
                        ExternalToggleText(
                            originalText: "at \(shortTimePM(prayer.startTime))",
                            toggledText: timeUntilStartString,
                            externalTrigger: $textTrigger,  // Pass the binding
                            fontDesign: .rounded,
                            fontWeight: .thin,
                            hapticFeedback: true
                        )
                        .foregroundStyle(.primary)/*.foregroundStyle(.secondary)*/
                    }
                    
                    if isMissedPrayer {
                        Text("Missed")
                            .fontDesign(.rounded)
                            .fontWeight(.thin)
                            .foregroundStyle(.primary)/*.foregroundStyle(.secondary)*/
                    }
                }
            }
                
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 200, height: 200)
                .onTapGesture {
//                    textTrigger.toggle()  // Toggle the trigger
                    handleTap()
                }
            */
            
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
                        checkToTriggerQiblaHaptic(aligned: newIsAligned)
                    }

                    .onTapGesture {
                        showQiblaMap = true
                    }
                    // Adding a larger tappable area without extra views
                    .frame(width: 44, height: 44) // Adjust as needed to expand tappable area

                    .fullScreenCover(isPresented: $showQiblaMap) {
                        LocationMapContentView()
                        .onAppear {
                            print("showqiblamap (from qibla arrow): \(showQiblaMap)")
                            sharedState.showingPulseView = false
                        }
                        .onDisappear{
                            sharedState.showingPulseView = true
                        }
                    }
            }
            
            
        }

        .onAppear {
//            startPulseAnimation()
            // Start DisplayLink
//            displayLink.start { newTime in
//                withAnimation(.linear(duration: 0.1)) {
//                    currentTime = newTime
//                }
//            }
            locationManager.startUpdating() // Start location updates
            sharedState.showingPulseView = true
        }
//        .onChange(of: progressZone) { _, _ in
//            startPulseAnimation()
//        }
        .onDisappear {
//            timer?.invalidate()
//            timer = nil
//            displayLink.stop()
            sharedState.showingPulseView = false
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
        
//        PulseCircleView(
//            prayer: prayer
////            toggleCompletion: {}
//        )
//        .environmentObject(SharedStateClass())

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
//                        sharedState.showingOtherPages = false
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
