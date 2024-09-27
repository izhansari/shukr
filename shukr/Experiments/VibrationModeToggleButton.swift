//import SwiftUI
//
//struct VibrationModeToggleButton: View {
//    // Define the vibration modes
//    enum VibrationModes {
//        case high, medium, low, off
//    }
//
//    @State private var currentVibrationMode: VibrationModes = .off
//
//    // Function to toggle between vibration modes
//    private func toggleVibrationMode() {
//        switch currentVibrationMode {
//        case .off:
//            currentVibrationMode = .low
//        case .low:
//            currentVibrationMode = .medium
//        case .medium:
//            currentVibrationMode = .high
//        case .high:
//            currentVibrationMode = .off
//        }
//    }
//
//    // Function to get the appropriate SF Symbol based on the mode
//    private func getIconForVibrationMode() -> String {
//        switch currentVibrationMode {
//        case .high:
//            return "speaker.wave.3.fill"  // High mode icon
//        case .medium:
//            return "speaker.wave.2.fill"  // Medium mode icon
//        case .low:
//            return "speaker.wave.1.fill"  // Low mode icon
//        case .off:
//            return "speaker.slash.fill"   // Off mode icon
//        }
//    }
//
//    var body: some View {
//        Button(action: {
//            toggleVibrationMode()
//        }) {
////            Image(systemName: getIconForMode())
////                .font(.system(size: 40))  // Adjust the size as needed
////                .foregroundColor(.blue)    // Customize color if needed
//            Image(systemName: getIconForVibrationMode())
//                .font(.system(size: 24))
//                .foregroundColor(.blue)
//                .padding()
//        }
//        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
//        .cornerRadius(15)
//        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 10)
////        .padding()
//    }
//}
//
////struct ContentView: View {
////    var body: some View {
////    }
////}
//
////struct ContentView_Previews: PreviewProvider {
////    static var previews: some View {
////        VibrationModeToggleButton()
////    }
////}
//
//
//#Preview {
//    VibrationModeToggleButton()
//}
