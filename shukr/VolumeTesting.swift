import SwiftUI
import AVFoundation
import MediaPlayer

// Volume observer to track system volume changes
class VolumeObserver: ObservableObject {
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var observer: NSKeyValueObservation?

    init() {
        observer = AVAudioSession.sharedInstance().observe(\.outputVolume) { [weak self] _, _ in
            self?.volume = AVAudioSession.sharedInstance().outputVolume
        }

        // Set up audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    deinit {
        observer?.invalidate()
    }
}

func setVolume(to volumeLevel: Float) {
    let volumeView = MPVolumeView()

    if let volumeSlider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
        volumeSlider.value = volumeLevel // Set the volume level (0.0 to 1.0)
    }
}

struct VolumeTesting: View {
    
    // State properties
    @State private var previousVolume: Float = AVAudioSession.sharedInstance().outputVolume
    @State private var currentVolume: Float = AVAudioSession.sharedInstance().outputVolume
    @ObservedObject private var volumeObserver = VolumeObserver() // Moved here to observe changes

    func startMonitoringVolume() {
        // Activate the audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
            try AVAudioSession.sharedInstance().setActive(true)
            print("Audio session activated")
        } catch {
            print("Failed to set up audio session")
        }

        // Monitor volume changes
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { notification in
            let newVolume = volumeObserver.volume // Fixed reference to the observer's volume
            print("New Volume: \(volumeObserver.volume)")

            // Logic for detecting volume button press
            if newVolume > previousVolume {
                print("Up button was pressed")
            } else if newVolume < previousVolume {
                print("Down button was pressed")
            }

            // Reset volume if needed
            previousVolume = newVolume
        }
    }

    func resetVolumeTo(_ level: Float) {
        let volumeView = MPVolumeView(frame: .zero)
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.value = level
        }
    }

    var body: some View {
        VStack {
            Text("Current volume: \(volumeObserver.volume, specifier: "%.2f")")
                .font(.title3)
                .padding(.bottom, 40)
                .foregroundColor(.gray)

            Button(action: {
                setVolume(to: 0.75) // Set volume to 75%
            }) {
                Text("Set Volume to 75%")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .padding()
                    .background(Color.gray.opacity(0.2)) // Optional: Add a background
                    .cornerRadius(10) // Optional: Add rounded corners
            }
            .padding(.bottom, 20)
            .onAppear {
                startMonitoringVolume()
            }
        }
    }
}

// Preview
#Preview {
    VolumeTesting()
}
