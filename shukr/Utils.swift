//import SwiftUI
//import AudioToolbox
//
//// Utility Functions
//func roundToTwo(val: Double) -> Double {
//    return ((val * 100.0).rounded() / 100.0)
//}
//
//// Vibration Feedback
//enum HapticFeedbackType: String, CaseIterable, Identifiable {
//    case light = "Light"
//    case medium = "Medium"
//    case heavy = "Heavy"
//    case soft = "Soft"
//    case rigid = "Rigid"
//    case success = "Success"
//    case warning = "Warning"
//    case error = "Error"
//    case vibrate = "Vibrate"
//    
//    var id: String { self.rawValue }
//}
//
//let impactFeedbackGenerator = UIImpactFeedbackGenerator()
//let notificationFeedbackGenerator = UINotificationFeedbackGenerator()
//
//func triggerSomeVibration(type: HapticFeedbackType, vibrateToggle: Bool) {
//    if vibrateToggle {
//        switch type {
//        case .light:
//            impactFeedbackGenerator.impactOccurred(intensity: 0.5)
//        case .medium:
//            impactFeedbackGenerator.impactOccurred(intensity: 0.75)
//        case .heavy:
//            impactFeedbackGenerator.impactOccurred(intensity: 1.0)
//        case .soft:
//            impactFeedbackGenerator.impactOccurred(intensity: 0.3)
//        case .rigid:
//            impactFeedbackGenerator.impactOccurred(intensity: 0.9)
//        case .success:
//            notificationFeedbackGenerator.notificationOccurred(.success)
//        case .warning:
//            notificationFeedbackGenerator.notificationOccurred(.warning)
//        case .error:
//            notificationFeedbackGenerator.notificationOccurred(.error)
//        case .vibrate:
//            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
//        }
//    }
//}
//
//// Custom Toggle Button
//func toggleButton(_ label: String, isOn: Binding<Bool>, color: Color, checks: Bool) -> some View {
//    Toggle(isOn: isOn) {
//        if checks { Text(isOn.wrappedValue ? "✓\(label)" : "✗\(label)") }
//        else { Text(isOn.wrappedValue ? "\(label)" : "\(label)") }
//    }
//    .toggleStyle(.button)
//    .tint(color)
//}
