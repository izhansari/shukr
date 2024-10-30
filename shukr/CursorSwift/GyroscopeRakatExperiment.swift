//import SwiftUI
//import CoreMotion
//import CoreLocation
//import MapKit
//
//struct StoredLocation: Identifiable, Codable {
//    var id: UUID
//    let latitude: Double
//    let longitude: Double
//    let timestamp: Date
//    
//    init(latitude: Double, longitude: Double, timestamp: Date) {
//        self.id = UUID()
//        self.latitude = latitude
//        self.longitude = longitude
//        self.timestamp = timestamp
//    }
//}
//
//struct GyroscopeRakatExperiment: View {
//    @StateObject private var settings = RakatSettings()
//    @StateObject private var motionManager: MotionManager
//    // Add back these objects
//    @StateObject private var locationManager = PrayerLocationManager()
//    @State private var showingMap = false
//    @State private var storedLocations: [StoredLocation] = []
//    
//    init() {
//        let settings = RakatSettings()
//        _settings = StateObject(wrappedValue: settings)
//        _motionManager = StateObject(wrappedValue: MotionManager(settings: settings))
//    }
//    
//    var body: some View {
//        NavigationStack {
//            ScrollView {
//                VStack {
//                    // Debug Information - Now at the top
//                    Group {
//                        Text("Debug Information")
//                            .font(.headline)
//                        
//                        VStack(alignment: .leading, spacing: 8) {
//                            Text("Position Requirements:")
//                                .fontWeight(.medium)
//                            
//                            HStack(spacing: 20) {
//                                // Standing Column
//                                VStack(alignment: .leading) {
//                                    let isStandingPitch = motionManager.pitch >= settings.standingPitchRange.lowerBound &&
//                                     motionManager.pitch <= settings.standingPitchRange.upperBound
//                                    let isStandingVertical = motionManager.debugGravityInfo.verticalness < settings.standingVerticalness
//
//                                    Text("Standing:")
//                                        .foregroundColor(isStandingPitch && isStandingVertical ? .green : .gray)
//                                        .fontWeight(.medium)
//                                    Text("• Pitch: \(Int(settings.standingPitchRange.lowerBound))° to \(Int(settings.standingPitchRange.upperBound))°")
//                                        .foregroundColor(isStandingPitch ? .green : .gray)
//                                    Text("(Current: \(String(format: "%.1f°", motionManager.pitch)))")
//                                        .font(.caption)
//                                        .foregroundColor(isStandingPitch ? .green : .gray)
//                                    
//                                    Text("• Verticalness < \(settings.standingVerticalness, specifier: "%.2f")")
//                                        .foregroundColor(isStandingVertical ? .green : .gray)
//                                    Text("(Current: \(String(format: "%.2f", motionManager.debugGravityInfo.verticalness)))")
//                                        .font(.caption)
//                                        .foregroundColor(isStandingVertical ? .green : .gray)
//                                    
//                                    Text("• Duration: \(settings.standingDuration, specifier: "%.1f")s")
//                                        .foregroundColor(motionManager.debugTimeStanding >= settings.standingDuration ? .green : .gray)
//                                    Text("(Current: \(String(format: "%.1f", motionManager.debugTimeStanding))s)")
//                                        .font(.caption)
//                                        .foregroundColor(motionManager.debugTimeStanding >= settings.standingDuration ? .green : .gray)
//                                }
//                                
//                                // Sitting Column
//                                VStack(alignment: .leading) {
//                                    let isSittingPitch = motionManager.pitch >= settings.sittingPitchRange.lowerBound &&
//                                     motionManager.pitch <= settings.sittingPitchRange.upperBound
//                                    let isSittingHorizontal = motionManager.debugGravityInfo.horizontalness < settings.sittingHorizontalness
//                                    
//                                    Text("Sitting:")
//                                        .foregroundColor(isSittingPitch && isSittingHorizontal ? .blue : .gray)
//                                        .fontWeight(.medium)
//                                    Text("• Pitch: \(Int(settings.sittingPitchRange.lowerBound))° to \(Int(settings.sittingPitchRange.upperBound))°")
//                                        .foregroundColor(isSittingPitch ? .blue : .gray)
//                                    Text("(Current: \(String(format: "%.1f°", motionManager.pitch)))")
//                                        .font(.caption)
//                                        .foregroundColor(isSittingPitch ? .blue : .gray)
//                                    
//                                    Text("• Horizontalness < \(settings.sittingHorizontalness, specifier: "%.2f")")
//                                        .foregroundColor(isSittingHorizontal ? .blue : .gray)
//                                    Text("(Current: \(String(format: "%.2f", motionManager.debugGravityInfo.horizontalness)))")
//                                        .font(.caption)
//                                        .foregroundColor(isSittingHorizontal ? .blue : .gray)
//                                    
//                                    Text("• Duration: \(settings.sittingDuration, specifier: "%.1f")s")
//                                        .foregroundColor(motionManager.debugTimeSitting >= settings.sittingDuration ? .blue : .gray)
//                                    Text("(Current: \(String(format: "%.1f", motionManager.debugTimeSitting))s)")
//                                        .font(.caption)
//                                        .foregroundColor(motionManager.debugTimeSitting >= settings.sittingDuration ? .blue : .gray)
//                                }
//                            }
//                            .padding()
//                            .background(Color.gray.opacity(0.1))
//                            .cornerRadius(10)
//                            
////                            Text("Standing Timer: \(String(format: "%.1f", motionManager.debugTimeStanding))s")
////                            Text("Need \(settings.standingDuration, specifier: "%.1f")s in position to validate")
//                            
//                            Text("Rakat Will Increment When...")
//                                .fontWeight(.medium)
//                            
//                            if !motionManager.hasSatDuringRakat {
//                                // Haven't sat long enough yet - this is the next step
//                                Text("1. ⬅️ Hold sitting position for \(settings.sittingDuration, specifier: "%.1f")s")
//                                Text("2. Move to standing position")
//                                Text("3. Hold standing for \(settings.standingDuration, specifier: "%.1f")s")
//                            } else if motionManager.lastPosition == .sitting {
//                                // Have sat long enough but still sitting
//                                Text("1. ✅ Held sitting position for \(settings.sittingDuration, specifier: "%.1f")s")
//                                Text("2. ⬅️ Move to standing position")
//                                Text("3. Hold standing for \(settings.standingDuration, specifier: "%.1f")s")
//                            } else if motionManager.lastPosition == .standing && motionManager.debugTimeStanding <= settings.standingDuration {
//                                // In standing but not held long enough
//                                Text("1. ✅ Held sitting position for \(settings.sittingDuration, specifier: "%.1f")s")
//                                Text("2. ✅ Moved to standing position")
//                                Text("3. ⬅️ Hold standing for \(String(format: "%.1f", settings.standingDuration - motionManager.debugTimeStanding))s more")
//                            }
//                        }
//                        .padding()
//                        .background(Color.gray.opacity(0.1))
//                        .cornerRadius(10)
//                    }
//                    .padding()
//                    
//                    // Rakat Tracking Status
//                    Group {
//                        Text("Rakat Tracking")
//                            .font(.headline)
//                        
//                        VStack(alignment: .leading, spacing: 8) {
//                            Text("Current Position: \(motionManager.lastPosition.description)")
//                                .foregroundColor(motionManager.lastPosition.color)
//                            
//                            Text("Status: \(motionManager.trackingStatus)")
//                                .foregroundColor(.primary)
//                            
//                            Text("Rakats Completed: \(motionManager.rakatCount)")
//                                .font(.headline)
//                                .foregroundColor(.blue)
//                            
//                            if !motionManager.rakatTimes.isEmpty {
//                                Text("Last Rakat Duration: \(String(format: "%.1f", motionManager.rakatTimes.last ?? 0)) seconds")
//                            }
//                            
//                            Text("Pitch Angle: \(String(format: "%.1f", motionManager.pitch))°")
//                                .font(.caption)
//                        }
//                        .padding()
//                        .background(Color.gray.opacity(0.1))
//                        .cornerRadius(10)
//                        
//                        Button(action: {
//                            if motionManager.isRecording {
//                                motionManager.stopRecording()
//                            } else {
//                                motionManager.startRecording()
//                            }
//                        }) {
//                            Text(motionManager.isRecording ? "Stop Recording" : "Start Recording")
//                                .padding()
//                                .background(motionManager.isRecording ? Color.red : Color.green)
//                                .foregroundColor(.white)
//                                .cornerRadius(10)
//                        }
//                        .padding()
//                        
//                        Button("Reset Count") {
//                            motionManager.resetCount()
//                        }
//                        .padding()
//                        .background(Color.orange)
//                        .foregroundColor(.white)
//                        .cornerRadius(10)
//                    }
//                    .padding()
//                    
//                    // Replace circle with Rakat Details Table
//                    Group {
//                        Text("Rakat Details")
//                            .font(.headline)
//                        
//                        if motionManager.rakatDetails.isEmpty {
//                            Text("No rakats completed yet")
//                                .foregroundColor(.gray)
//                                .padding()
//                        } else {
//                            VStack(alignment: .leading, spacing: 4) {
//                                // Header
//                                HStack {
//                                    Text("#").frame(width: 30, alignment: .leading)
//                                    Text("Time").frame(width: 70, alignment: .leading)
//                                    Text("Duration").frame(width: 70, alignment: .leading)
//                                    Text("Standing").frame(width: 90, alignment: .leading)
//                                    Text("Sitting").frame(width: 90, alignment: .leading)
//                                }
//                                .font(.caption)
//                                .foregroundColor(.gray)
//                                
//                                // Rows
//                                ForEach(Array(motionManager.rakatDetails.enumerated()), id: \.element.timestamp) { index, rakat in
//                                    HStack {
//                                        Text("\(index + 1)")
//                                            .frame(width: 30, alignment: .leading)
//                                        Text(rakat.timestamp, style: .time)
//                                            .frame(width: 70, alignment: .leading)
//                                        Text(String(format: "%.1fs", rakat.duration))
//                                            .frame(width: 70, alignment: .leading)
//                                        Text(rakat.standingMetric)
//                                            .frame(width: 90, alignment: .leading)
//                                        Text(rakat.sittingMetric)
//                                            .frame(width: 90, alignment: .leading)
//                                    }
//                                    .font(.caption)
//                                }
//                            }
//                            .padding()
//                            .background(Color.gray.opacity(0.1))
//                            .cornerRadius(10)
//                        }
//                    }
//                    .padding()
//                    
////                    // Original circle and current values
////                    Circle()
////                        .fill(getCircleColor())
////                        .frame(width: 100, height: 100)
////                        .padding()
////                    
////                    Group {
////                        Text("Current Values").font(.headline)
////                        VStack(alignment: .leading) {
////                            Text("Height: \(String(format: "%.2f", motionManager.height))m")
////                            Text("Pitch: \(String(format: "%.2f", motionManager.pitch))°")
////                            Text("Roll: \(String(format: "%.2f", motionManager.roll))°")
////                            Text("Is Praying: \(motionManager.isPrayingPosition ? "Yes" : "No")")
////                        }
////                    }
////                    .padding()
////                    
////                    if !motionManager.isRecording && (motionManager.endHeight != 0 || motionManager.endPitch != 0) {
////                        Group {
////                            Text("Position Changes").font(.headline)
////                            VStack(alignment: .leading) {
////                                Text("Height: \(String(format: "%.2f", motionManager.endHeight - motionManager.startHeight))m")
////                                Text("Pitch: \(String(format: "%.2f", motionManager.endPitch - motionManager.startPitch))°")
////                                Text("Roll: \(String(format: "%.2f", motionManager.endRoll - motionManager.startRoll))°")
////                            }
////                        }
////                        .padding()
////                        
////                        Group {
////                            Text("Min/Max Values").font(.headline)
////                            VStack(alignment: .leading) {
////                                Text("Height: \(String(format: "%.2f", motionManager.minHeight))m to \(String(format: "%.2f", motionManager.maxHeight))m")
////                                Text("Pitch: \(String(format: "%.2f", motionManager.minPitch))° to \(String(format: "%.2f", motionManager.maxPitch))°")
////                                Text("Roll: \(String(format: "%.2f", motionManager.minRoll))° to \(String(format: "%.2f", motionManager.maxRoll))°")
////                            }
////                        }
////                        .padding()
////                    }
//                    
//                    // Add Store Location button
//                    Button(action: storeCurrentLocation) {
//                        Text("Store Location")
//                            .padding()
//                            .background(Color.blue)
//                            .foregroundColor(.white)
//                            .cornerRadius(10)
//                    }
//                    .padding()
//                    
//                    // Add Settings Section at bottom
//                    Group {
//                        Text("Adjust Requirements")
//                            .font(.headline)
//                        
//                        VStack(spacing: 20) {
//                            // Standing Settings
//                            VStack(alignment: .leading) {
//                                Text("Standing Requirements")
//                                    .fontWeight(.medium)
//                                    .foregroundColor(.green)
//                                
//                                Text("Pitch Range: \(Int(settings.standingPitchRange.lowerBound))° to \(Int(settings.standingPitchRange.upperBound))°")
//                                    .font(.caption)
//                                Slider(value: Binding(
//                                    get: { settings.standingPitchRange.lowerBound },
//                                    set: { settings.standingPitchRange = $0...settings.standingPitchRange.upperBound }
//                                ), in: 0...90)
//                                Slider(value: Binding(
//                                    get: { settings.standingPitchRange.upperBound },
//                                    set: { settings.standingPitchRange = settings.standingPitchRange.lowerBound...$0 }
//                                ), in: 90...180)
//                                
//                                Text("Verticalness Threshold: \(settings.standingVerticalness, specifier: "%.2f")")
//                                    .font(.caption)
//                                Slider(value: $settings.standingVerticalness, in: 0...1)
//                                
//                                Text("Duration: \(settings.standingDuration, specifier: "%.1f")s")
//                                    .font(.caption)
//                                Slider(value: $settings.standingDuration, in: 1...10)
//                            }
//                            
//                            // Sitting Settings
//                            VStack(alignment: .leading) {
//                                Text("Sitting Requirements")
//                                    .fontWeight(.medium)
//                                    .foregroundColor(.blue)
//                                
//                                Text("Pitch Range: \(Int(settings.sittingPitchRange.lowerBound))° to \(Int(settings.sittingPitchRange.upperBound))°")
//                                    .font(.caption)
//                                Slider(value: Binding(
//                                    get: { settings.sittingPitchRange.lowerBound },
//                                    set: { settings.sittingPitchRange = $0...settings.sittingPitchRange.upperBound }
//                                ), in: -90...0)
//                                Slider(value: Binding(
//                                    get: { settings.sittingPitchRange.upperBound },
//                                    set: { settings.sittingPitchRange = settings.sittingPitchRange.lowerBound...$0 }
//                                ), in: 0...90)
//                                
//                                Text("Horizontalness Threshold: \(settings.sittingHorizontalness, specifier: "%.2f")")
//                                    .font(.caption)
//                                Slider(value: $settings.sittingHorizontalness, in: 0...1)
//                                
//                                Text("Duration: \(settings.sittingDuration, specifier: "%.1f")s")
//                                    .font(.caption)
//                                Slider(value: $settings.sittingDuration, in: 0...5)
//                            }
//                        }
//                        .padding()
//                        .background(Color.gray.opacity(0.1))
//                        .cornerRadius(10)
//                    }
//                    .padding()
//                }
//            }
//            .navigationTitle("Rakat Experiment")
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button(action: { showingMap = true }) {
//                        Image(systemName: "map")
//                    }
//                }
//            }
//            .sheet(isPresented: $showingMap) {
//                LocationMapView(locations: storedLocations)
//            }
//        }
//    }
//    
//    private func getCircleColor() -> Color {
//        let normalizedHeight = min(max(motionManager.height / 2, 0), 1)
//        return Color(.sRGB, 
//                    red: Double(normalizedHeight),
//                    green: Double(normalizedHeight),
//                    blue: Double(normalizedHeight))
//    }
//    
//    private func storeCurrentLocation() {
//        guard let location = locationManager.location else { return }
//        let newLocation = StoredLocation(
//            latitude: location.coordinate.latitude,
//            longitude: location.coordinate.longitude,
//            timestamp: Date()
//        )
//        storedLocations.append(newLocation)
//    }
//}
//
//class MotionManager: ObservableObject {
//    private let motionManager = CMMotionManager()
//    private let altimeter = CMAltimeter()
//    private let settings: RakatSettings
//    
//    // Current values
//    @Published var height: Double = 0
//    @Published var pitch: Double = 0
//    @Published var roll: Double = 0
//    @Published var isRecording = false
//    @Published var isPrayingPosition = false
//    
//    // Start position
//    @Published var startHeight: Double = 0
//    @Published var startPitch: Double = 0
//    @Published var startRoll: Double = 0
//    
//    // End position
//    @Published var endHeight: Double = 0
//    @Published var endPitch: Double = 0
//    @Published var endRoll: Double = 0
//    
//    // Min/Max values during recording
//    @Published var minHeight: Double = .infinity
//    @Published var maxHeight: Double = -.infinity
//    @Published var minPitch: Double = .infinity
//    @Published var maxPitch: Double = -.infinity
//    @Published var minRoll: Double = .infinity
//    @Published var maxRoll: Double = -.infinity
//    
//    // Add these properties
//    @Published var positionCount: Int = 0
//    @Published var rakatCount: Int = 0
//    @Published var rakatTimes: [TimeInterval] = []  // Store duration of each rakat
//    @Published var lastPosition: PositionState = .unknown
//    private var currentRakatStartTime: Date?
//    private var lastPositionChangeTime: Date?
//    private var standingStartTime: Date?
//    private var deviceMotion: CMDeviceMotion?
//    
//    // Add these properties to MotionManager
//    @Published var debugGravityInfo: (verticalness: Double, horizontalness: Double) = (0, 0)
//    @Published var debugTimeStanding: Double = 0
//    
//    // Add this property
//    @Published var hasSatDuringRakat: Bool = false
//    
//    // Add this struct to MotionManager
//    @Published var rakatDetails: [RakatDetail] = []
//    
//    // Add these properties
//    private var lastSittingPitch: Double = 0
//    private var lastSittingHorizontalness: Double = 0
//    
//    // Add this constant at the top of the class
//    private let standingValidationTime: Double = 5.0
//    
//    // Add these properties
//    private let sittingValidationTime: Double = 2.0
//    @Published var sittingStartTime: Date?
//    @Published var debugTimeSitting: Double = 0
//    
//    enum PositionState {
//        case standing   // When pitch is near ±90° (phone vertical)
//        case sitting    // When pitch is near 0° (phone horizontal)
//        case unknown
//    }
//    
//    // Add this function
//    func resetCount() {
//        positionCount = 0
//        rakatCount = 0
//        rakatTimes = []
//        lastPosition = .unknown
//        lastPositionChangeTime = nil
//        currentRakatStartTime = nil
//        // Add to existing reset function
//        hasSatDuringRakat = false
//        // Add to existing reset
//        rakatDetails.removeAll()
//        // Add to existing reset
//        lastSittingPitch = 0
//        lastSittingHorizontalness = 0
//    }
//    
//    init(settings: RakatSettings) {
//        self.settings = settings
//    }
//    
//    private func determinePosition() -> PositionState {
//        guard let motion = deviceMotion else { return .unknown }
//        
//        let gravity = motion.gravity
//        let verticalness = abs(gravity.z)
//        let horizontalness = sqrt(gravity.x * gravity.x + gravity.y * gravity.y)
//        
//        debugGravityInfo = (verticalness, horizontalness)
//        
//        // Use settings for thresholds
//        if pitch >= settings.standingPitchRange.lowerBound && 
//           pitch <= settings.standingPitchRange.upperBound && 
//           verticalness < settings.standingVerticalness {
//            return .standing
//        }
//        else if pitch >= settings.sittingPitchRange.lowerBound && 
//                pitch <= settings.sittingPitchRange.upperBound && 
//                horizontalness < settings.sittingHorizontalness {
//            return .sitting
//        }
//        
//        return .unknown
//    }
//    
//    private func updatePosition() {
//        let currentPosition = determinePosition()
//        
//        if currentPosition == .sitting {
//            if sittingStartTime == nil {
//                sittingStartTime = Date()
//            } else if let startTime = sittingStartTime {
//                debugTimeSitting = Date().timeIntervalSince(startTime)
//                
//                if debugTimeSitting > settings.sittingDuration {
//                    hasSatDuringRakat = true
//                    lastSittingPitch = pitch
//                    lastSittingHorizontalness = debugGravityInfo.horizontalness
//                }
//            }
//        } else {
//            sittingStartTime = nil
//            debugTimeSitting = 0
//        }
//        
//        if currentPosition == .standing {
//            if standingStartTime == nil {
//                standingStartTime = Date()
//            } else if let startTime = standingStartTime {
//                debugTimeStanding = Date().timeIntervalSince(startTime)
//                
//                if debugTimeStanding > settings.standingDuration && hasSatDuringRakat {
//                    // When incrementing rakat, store the details
//                    let detail = RakatDetail(
//                        timestamp: Date(),
//                        duration: Date().timeIntervalSince(currentRakatStartTime ?? Date()),
//                        standingMetric: String(format: "P:%.0f°/V:%.2f", pitch, debugGravityInfo.verticalness),
//                        sittingMetric: String(format: "P:%.0f°/H:%.2f", lastSittingPitch, lastSittingHorizontalness)
//                    )
//                    rakatDetails.append(detail)
//                    
//                    rakatCount += 1
//                    
//                    // Calculate and store rakat duration
//                    if let rakatStartTime = currentRakatStartTime {
//                        let duration = Date().timeIntervalSince(rakatStartTime)
//                        rakatTimes.append(duration)
//                    }
//                    
//                    // Reset for next rakat
//                    hasSatDuringRakat = false
//                    currentRakatStartTime = Date()
//                    lastPositionChangeTime = Date()
//                }
//            }
//        } else {
//            standingStartTime = nil
//            debugTimeStanding = 0
//        }
//        
//        lastPosition = currentPosition
//    }
//    
//    func startRecording() {
//        guard motionManager.isDeviceMotionAvailable else { return }
//        
//        // Reset min/max values
//        minHeight = .infinity
//        maxHeight = -.infinity
//        minPitch = .infinity
//        maxPitch = -.infinity
//        minRoll = .infinity
//        maxRoll = -.infinity
//        
//        // Store start position
//        startHeight = height
//        startPitch = pitch
//        startRoll = roll
//        
//        isRecording = true
//        
//        // Reset count
//        resetCount()
//        
//        // Start device motion updates
//        motionManager.deviceMotionUpdateInterval = 0.1
//        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
//            guard let self = self, let motion = motion else { return }
//            
//            self.deviceMotion = motion  // Store the motion data
//            self.pitch = motion.attitude.pitch * 180 / .pi
//            self.roll = motion.attitude.roll * 180 / .pi
//            
//            // Update min/max values
//            self.minPitch = min(self.minPitch, self.pitch)
//            self.maxPitch = max(self.maxPitch, self.pitch)
//            self.minRoll = min(self.minRoll, self.roll)
//            self.maxRoll = max(self.maxRoll, self.roll)
//            
//            self.isPrayingPosition = self.checkPrayerPosition()
//            self.updatePosition()
//        }
//        
//        if CMAltimeter.isRelativeAltitudeAvailable() {
//            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
//                guard let self = self, let data = data else { return }
//                self.height = data.relativeAltitude.doubleValue
//                
//                // Update min/max height
//                self.minHeight = min(self.minHeight, self.height)
//                self.maxHeight = max(self.maxHeight, self.height)
//            }
//        }
//    }
//    
//    func stopRecording() {
//        // Store end position
//        endHeight = height
//        endPitch = pitch
//        endRoll = roll
//        
//        isRecording = false
//        motionManager.stopDeviceMotionUpdates()
//        altimeter.stopRelativeAltitudeUpdates()
//    }
//    
//    private func checkPrayerPosition() -> Bool {
//        // Check if phone is tilted forward (pitch around -90°) and lower than initial position
//        let isPitchCorrect = pitch < -45 // Tilted forward
//        let isLowerThanStart = height < (startHeight - 0.5) // At least 0.5m lower than start
//        
//        return isPitchCorrect && isLowerThanStart
//    }
//    
//    var trackingStatus: String {
//        if !isRecording {
//            return "Not Recording - Press Start to begin tracking"
//        }
//        
//        if let startTime = standingStartTime {
//            // Changed from 1.5 to 5.0
//            let timeRemaining = max(0, standingValidationTime - Date().timeIntervalSince(startTime))
//            return String(format: "Validating standing position (%.1f seconds remaining)", timeRemaining)
//        }
//        
//        switch lastPosition {
//        case .standing:
//            return "In standing position - waiting for sujood"
//        case .sitting:
//            return "In sujood - waiting for standing"
//        case .unknown:
//            return "Move to standing or sujood position"
//        }
//    }
//}
//
//class PrayerLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
//    private let locationManager = CLLocationManager()
//    @Published var location: CLLocation?
//    
//    override init() {
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        location = locations.last
//    }
//}
//
//struct LocationMapView: View {
//    let locations: [StoredLocation]
//    @Environment(\.dismiss) var dismiss
//    
//    var body: some View {
//        NavigationStack {
//            Map {
//                ForEach(locations) { location in
//                    Marker("Prayer Location", coordinate: CLLocationCoordinate2D(
//                        latitude: location.latitude,
//                        longitude: location.longitude
//                    ))
//                }
//            }
//            .navigationTitle("Prayer Locations")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button("Done") {
//                        dismiss()
//                    }
//                }
//            }
//        }
//    }
//}
//
//struct GyroscopeRakatExperiment_Previews: PreviewProvider {
//    static var previews: some View {
//        GyroscopeRakatExperiment()
//    }
//}
//
//// Add these extensions for better display
//extension MotionManager.PositionState {
//    var description: String {
//        switch self {
//        case .standing:
//            return "Standing (Vertical)"
//        case .sitting:
//            return "Sitting/Sujood (Horizontal)"
//        case .unknown:
//            return "Unknown Position"
//        }
//    }
//    
//    var color: Color {
//        switch self {
//        case .standing:
//            return .green
//        case .sitting:
//            return .blue
//        case .unknown:
//            return .gray
//        }
//    }
//}
//
//// Add this struct to MotionManager
//struct RakatDetail {
//    let timestamp: Date
//    let duration: TimeInterval
//    let standingMetric: String
//    let sittingMetric: String
//}
//
//class RakatSettings: ObservableObject {
//    @Published var standingPitchRange: ClosedRange<Double> = 60...120
//    @Published var standingVerticalness: Double = 0.5
//    @Published var standingDuration: Double = 5.0
//    
//    @Published var sittingPitchRange: ClosedRange<Double> = -30...30
//    @Published var sittingHorizontalness: Double = 0.8
//    @Published var sittingDuration: Double = 2.0
//}
//
