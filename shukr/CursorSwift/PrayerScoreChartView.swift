//
//  PrayerScoreChartView.swift
//  shukr
//
//  Created by Izhan S Ansari on 3/5/25.
//


import SwiftUI
import SwiftData
import Charts

struct SimpleDailyScoreView: View {
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @Environment(\.modelContext) private var context
    @EnvironmentObject var viewModel: PrayerViewModel
    @Query private var scores: [DailyPrayerScore]
    
    @State private var selectedDate = Date()
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 20) {
            // Date navigation
            HStack {
                Button(action: previousDay) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text(formattedDate)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: nextDay) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .disabled(Calendar.current.isDate(selectedDate, inSameDayAs: Date()) )
                .opacity(Calendar.current.isDate(selectedDate, inSameDayAs: Date())  ? 0 : 1)
            }
            .padding(.horizontal)
            
            // Score display
            VStack(spacing: 10) {
//                Text("Prayer Score")
//                    .font(.headline)
//                    .foregroundColor(.secondary)
                
                Text(scoreDisplay)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundColor(scoreColor)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal)
            
            // Individual prayer scores
            VStack(spacing: 15) {
                ForEach(viewModel.orderedPrayerNames, id: \.self) { prayerName in
                    buildPrayerRow(for: prayerName)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal)
            
            Spacer()
            
//            // Generate data button
//            Button("Process Last 100 Days") {
//                processPastDaysData(days: 100)
//            }
//            .buttonStyle(.borderedProminent)
//            .padding()
        }
        .navigationTitle("Prayer Scores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Today") {
                    selectedDate = Date()
                }
            }
        }
    }
    
    // MARK: - Prayer Row
    
    @ViewBuilder
    private func buildPrayerRow(for prayerName: String) -> some View {
        let prayers = loadPrayerObjects(for: selectedDate)
        let prayer = prayers.first(where: { $0.name == prayerName })

//         var overlayCircleColor: Color {
//            if isFuturePrayer { return Color.secondary.opacity(0.01) }
//            return prayerObject.isCompleted ? prayerObject.getColorForPrayerScore() : Color.clear/*secondary.opacity(0.5)*/
//        }

//         var grayCircleStyle: Color {
//            if isFuturePrayer { return Color.secondary.opacity(0.2) }
//            return prayerObject.isCompleted ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.5)
//        }

        HStack {
            // Status Circle
            if let prayer = prayer {
                Button(action: {
                    viewModel.togglePrayerCompletion(for: prayer)
                }) {
                    Image(systemName: "circle")
                        .foregroundColor(outerCircleStyle(prayer: prayer))
                        .frame(width: 14, height: 14)
                        .fontWeight(.light)
                        .overlay {
                            Image(systemName: "circle.fill")
                                .resizable()
                                .foregroundStyle(getOverlayColor(prayer: prayer))
                                .frame(width: 12, height: 12)
                        }
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 24, height: 24, alignment: .leading)
            } else {
                // Fallback when prayer is nil
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    .frame(width: 14, height: 14)
                    .frame(width: 24, height: 24, alignment: .leading)
            }            // Prayer name
            Text(prayerName)
//                .font(.headline)
//                .foregroundColor(.primary)
                .font(.callout) //.callout
                .foregroundColor(.secondary.opacity(1)) //1
                .fontDesign(.rounded)
                .fontWeight(.light)

//            if let prayer = prayer, let engScore = prayer.englishScore {
//                Text(" (\(engScore))")
//                    .font(.headline)
//                    .foregroundColor(.secondary)
//            }
            
            Spacer()
            
            // Status icon
            if let prayer = prayer {
                if prayer.isCompleted {
                    if let engScore = prayer.gradeWord, let score = prayer.numberScore  {   // gradeWord: old rows store "Early" / "On time" / "Late"
                        Text("\(engScore)")
                            .font(.callout)
                            .foregroundColor(PrayerScoring.color(for: score))
                    }
//                    if let score = prayer.numberScore {
//                        // Show score percentage
//                        Text("\(Int(score * 100))%")
//                            .font(.callout)
//                            .foregroundColor(getColorForScore(score))
//                        
////                        Image(systemName: "checkmark.circle.fill")
////                            .foregroundColor(getColorForScore(score))
//                    }
//                    else {
//                        Text("Completed")
//                            .font(.callout)
//                            .foregroundColor(.gray)
//                    }
                } else if prayer.startTime > Date() {
                    Text("\(shortTimePM(prayer.startTime))")
                        .font(.callout)
                        .foregroundColor(.gray)
                }
            } else {
                Text("No Data")
                    .font(.callout)
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // Helper methods to calculate colors outside the view body
    private func outerCircleStyle(prayer: PrayerModel) -> Color {
        let isFuturePrayer = prayer.startTime > Date()
        if isFuturePrayer {
            return Color.secondary.opacity(0.2)
        }
        return prayer.isCompleted ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.5)
    }

    private func getOverlayColor(prayer: PrayerModel) -> Color {
        let isFuturePrayer = prayer.startTime > Date()
        if isFuturePrayer {
            return Color.secondary.opacity(0.01)
        }
        let color = prayer.isCompleted ? prayer.getColorForPrayerScore() : Color.clear
        
        // Apply opacity based on color and color scheme
        if color == .red && colorScheme == .dark {
            return color.opacity(0.5)
        } else if color == .yellow && colorScheme == .light {
            return color.opacity(1)
        } else {
            return color.opacity(0.7)
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private var scoreDisplay: String {
        if let score = getDailyScore() {
            return "\(Int(score * 100))%"
        } else {
            return "0%"
        }
    }
    
    private var scoreColor: Color {
        if let score = getDailyScore() {
            return getColorForScore(score)
        } else {
            return .gray
        }
    }
    
    private func getColorForScore(_ score: Double) -> Color {
        if score >= 0.9 {
            return .green
        } else if score >= 0.75 {
            return .yellow
        } else if score >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func getDailyScore() -> Double? {
        let startOfDay = calendar.startOfDay(for: selectedDate)
        
        let dailyScore = scores.first { score in
            calendar.isDate(score.date, inSameDayAs: startOfDay)
        }
        
        return dailyScore?.averageScore
    }
    
    private func loadPrayerObjects(for date: Date) -> [PrayerModel] {
        return viewModel.loadPrayerObjects(for: date)
    }
    
    private func previousDay() {
        if let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func nextDay() {
        if let newDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func processPastDaysData(days: Int) {
        let today = Date()
        
        // Process past days
        for dayOffset in 0..<days {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            viewModel.calculateDayScore(for: date)
        }
    }
}

#Preview {
    NavigationView {
        SimpleDailyScoreView()
            .modelContainer(for: DailyPrayerScore.self, inMemory: false)
    }
}
