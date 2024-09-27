//import SwiftUI
//
//class CombinedViewModel: ObservableObject {
//    @AppStorage("count", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
//    var tasbeeh: Int = 10
//
//    @Published var inactivityTimer: Timer? = nil
//    @Published var timeSinceLastInteraction: TimeInterval = 0
//    @Published var showInactivityAlert = false
//    @Published var countDownForAlert = 0
//    @Published var stoppedDueToInactivity: Bool = false
//    @Published var toggleInactivityTimer: Bool = false
//    @Published var offsetY: CGFloat = 0
//
//    var inactivityLimit: TimeInterval {
//        // Use the existing logic for inactivity limit
//        if tasbeeh > 10 && clickStats.count >= 5 {
//            let lastFiveClicks = clickStats.suffix(5)
//            let lastFiveMovingAvg = lastFiveClicks.reduce(0.0) { sum, stat in
//                sum + stat.tpc
//            } / Double(lastFiveClicks.count)
//
//            return max(lastFiveMovingAvg * 3, 15)
//        } else {
//            return 20
//        }
//    }
//
//    typealias newClickData = (date: Date, pauseTime: TimeInterval, tpc: TimeInterval)
//    @Published var clickStats: [newClickData] = []
//
//    func inactivityTimerHandler(run: String, stopTimer: @escaping () -> Void) {
//        if toggleInactivityTimer {
//            switch run {
//            case "restart":
//                print("start inactivity timer with limit of \(inactivityLimit)")
//                inactivityTimer?.invalidate()
//                showInactivityAlert = false
//                timeSinceLastInteraction = 0
//                var localCountDown = 11
//                
//                inactivityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
//                    self.timeSinceLastInteraction += 1.0
//                    if self.offsetY != 0 {
//                        print("holding screen down -- reset timeSinceLastInteraction from \(self.timeSinceLastInteraction) to 0.")
//                        self.timeSinceLastInteraction = 0
//                    }
//                    if self.timeSinceLastInteraction >= self.inactivityLimit {
//                        self.showInactivityAlert = true
//                        localCountDown -= 1
//                        self.countDownForAlert = localCountDown
//                    }
//                    if localCountDown <= 0 {
//                        self.stoppedDueToInactivity = true
//                        stopTimer()
//                    }
//                }
//            case "stop":
//                print("stopping inactivity timer")
//                inactivityTimer?.invalidate()
//            default:
//                print("yo bro invalid use of inactivityTimerHandler func")
//            }
//        } else {
//            print("Not tracking inactivity cuz Bool set to \(toggleInactivityTimer)")
//        }
//    }
//}
