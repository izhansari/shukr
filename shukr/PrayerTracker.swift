import SwiftUI
import CoreMotion

struct GyroscopeRakatExperiment: View {
    @StateObject private var motionManager = MotionManager()
    
    var body: some View {
        VStack {
            // Status circle that changes color based on height
            Circle()
                .fill(getCircleColor())
                .frame(width: 100, height: 100)
                .padding()
            
            // Display motion data
            VStack(alignment: .leading) {
                Text("Height: \(String(format: "%.2f", motionManager.height))m")
                Text("Pitch: \(String(format: "%.2f", motionManager.pitch))°")
                Text("Roll: \(String(format: "%.2f", motionManager.roll))°")
                Text("Is Praying: \(motionManager.isPrayingPosition ? "Yes" : "No")")
            }
            .padding()
            
            // Start/Stop button
            Button(action: {
                if motionManager.isRecording {
                    motionManager.stopRecording()
                } else {
                    motionManager.startRecording()
                }
            }) {
                Text(motionManager.isRecording ? "Stop Recording" : "Start Recording")
                    .padding()
                    .background(motionManager.isRecording ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }
    
    private func getCircleColor() -> Color {
        // Change color based on height (darker as phone gets lower)
        let normalizedHeight = min(max(motionManager.height / 2, 0), 1)
        return Color(.sRGB, 
                    red: Double(normalizedHeight),
                    green: Double(normalizedHeight),
                    blue: Double(normalizedHeight))
    }
}

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    
    @Published var height: Double = 0
    @Published var pitch: Double = 0
    @Published var roll: Double = 0
    @Published var isRecording = false
    @Published var isPrayingPosition = false
    
    private var referenceHeight: Double = 0
    
    func startRecording() {
        guard motionManager.isDeviceMotionAvailable else { return }
        
        isRecording = true
        referenceHeight = height // Store initial height as reference
        
        // Start device motion updates
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            
            self?.pitch = motion.attitude.pitch * 180 / .pi
            self?.roll = motion.attitude.roll * 180 / .pi
            
            // Check if in prayer position (phone tilted forward and low)
            self?.isPrayingPosition = self?.checkPrayerPosition() ?? false
        }
        
        // Start relative altitude updates if available
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let data = data else { return }
                self?.height = data.relativeAltitude.doubleValue
            }
        }
    }
    
    func stopRecording() {
        isRecording = false
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }
    
    private func checkPrayerPosition() -> Bool {
        // Check if phone is tilted forward (pitch around -90°) and lower than initial position
        let isPitchCorrect = pitch < -45 // Tilted forward
        let isLowerThanStart = height < (referenceHeight - 0.5) // At least 0.5m lower than start
        
        return isPitchCorrect && isLowerThanStart
    }
}
