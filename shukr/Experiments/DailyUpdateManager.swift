import SwiftUI

// basically a timer that only fires once. then redone.
struct DailyUpdateManager: View {
    @State private var currentDate = Date()
    @State private var timer: Timer?

    var body: some View {
        VStack {
            Text("Today is: \(currentDate, formatter: dateFormatter)")
                .font(.title)
                .padding()
            
            Text("This view will update at midnight")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Simulate Date Change") {
                currentDate = Date().addingTimeInterval(86400) // Add one day
            }
            .padding()
        }
        .onAppear(perform: scheduleNextUpdate)
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }

    private func scheduleNextUpdate() {
        let calendar = Calendar.current
        if let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date().addingTimeInterval(86400)) {
            let timeInterval = midnight.timeIntervalSince(Date())
            timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { _ in
                currentDate = Date()
                scheduleNextUpdate() // Schedule the next update
            }
        }
    }
}

struct DailyUpdateManager_Previews: PreviewProvider {
    static var previews: some View {
        DailyUpdateManager()
    }
}
