//
//  PrayerEditorView.swift
//  shukr
//
//  Created on 1/17/25.
//


import SwiftUI
import SwiftData



struct PrayerEditorView: View { //prayerstreak_flag main viewer for the streaks. mostly for debugging reasons
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
    @EnvironmentObject var viewModel: PrayerViewModel
    @AppStorage("prayerStreak") var prayerStreak: Int = 0
    @AppStorage("maxPrayerStreak") var maxPrayerStreak: Int = 0
    @AppStorage("prayerStreakMode") var prayerStreakMode: Int = 1
    @AppStorage("dateOfMaxPrayerStreak") var dateOfMaxPrayerStreakTimeInterval: Double = Date().timeIntervalSince1970
    var dateOfMaxPrayerStreak: Date {
        get {
            return Date(timeIntervalSince1970: dateOfMaxPrayerStreakTimeInterval)
        }
        set {
            dateOfMaxPrayerStreakTimeInterval = newValue.timeIntervalSince1970
        }
    }
    var streakEndDateString: String {
        dateOfMaxPrayerStreak.formatted(.dateTime.day(.defaultDigits).month(.defaultDigits).year(.defaultDigits).locale(.current))
    }
    var streakBegDateString: String {
        let daysToGoBack = maxPrayerStreak / 5
        let newDate = Calendar.current.date(byAdding: .day, value: -daysToGoBack, to: dateOfMaxPrayerStreak)!
        return newDate.formatted(.dateTime.day(.defaultDigits).month(.defaultDigits).year(.defaultDigits).locale(.current))
    }
    @State private var selectedDate: Date = .now
    @State private var prayersForDate: [PrayerModel] = []
    
    @Query private var scores: [DailyPrayerScore]

    
    private func isFuturePrayer(for prayer: PrayerModel) -> Bool {
        prayer.startTime > Date()
    }
    
    // Status Circle Properties
    private func statusImageName(for prayer: PrayerModel) -> String {
        if isFuturePrayer(for: prayer) { return "circle" }
        return prayer.isCompleted ? "checkmark.circle.fill" : "circle"
    }
    
//    private func statusColor(for prayer: PrayerModel) -> Color {
//        if isFuturePrayer(for: prayer) { return Color.secondary.opacity(0.2) }
//        return prayer.isCompleted ? viewModel.getColorForPrayerScore(prayer.numberScore).opacity(/*colorScheme == .dark ? 0.5 : */0.70) : Color.secondary.opacity(0.5)
//    }
    private func statusColor(for prayer: PrayerModel) -> Color {
        if isFuturePrayer(for: prayer) { return Color.secondary.opacity(0.2) }
        return prayer.isCompleted ? prayer.getColorForPrayerScore().opacity(/*colorScheme == .dark ? 0.5 : */0.70) : Color.secondary.opacity(0.5)
    }
    
    private func outerCircleStyle(prayer: PrayerModel) -> Color {
        let isFuturePrayer = prayer.startTime > Date()
        if isFuturePrayer {
            return Color.secondary.opacity(0.2)
        }
        return prayer.isCompleted ? Color.secondary.opacity(0.5) : Color.secondary.opacity(0.5)
    }

    private func innerCircleColor(prayer: PrayerModel) -> Color {
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
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        
        let dailyScore = scores.first { score in
            Calendar.current.isDate(score.date, inSameDayAs: startOfDay)
        }
        
        return dailyScore?.averageScore
    }


    
    var body: some View {
        VStack {
            HStack{
                Text("Streak: \(prayerStreak)")
                Text("Max: \(maxPrayerStreak)")
                Text("from \(streakBegDateString) - \(streakEndDateString)")
            }
            
//            // Mode Selection
//            Picker("Streak Type", selection: $prayerStreakMode) {
//                Text("Level 1").tag(1)
//                Text("Level 2").tag(2)
//                Text("Level 3").tag(3)
//            }
//            .pickerStyle(.segmented)
//            .onChange(of: prayerStreakMode){ _, new in
//                viewModel.calculatePrayerStreak()
//            }

            // Date Picker
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.automatic)
                .padding()
                .onChange(of: selectedDate) { _, new in
                    fetchPrayersForDate()
                }
            
            // Score display

            VStack(spacing: 10) {
                Text("Prayer Score")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text(scoreDisplay)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundColor(scoreColor)
            }

            
            // List of Prayers for Selected Date
            List(prayersForDate) { prayer in
                HStack {
//                    Button(action: {
//                        //updatePrayerCompletion(prayer) //not using viewmodel's togglePrayerCompletion cuz it guards against stuff not in the timerange.
//                        viewModel.togglePrayerCompletion(for: prayer)
//                    }) {
//                        Image(systemName: statusImageName(for: prayer))
//                            .foregroundColor(statusColor(for: prayer))
//                            .frame(width: 24, height: 24, alignment: .leading)
//                            .overlay(
//                                Image(systemName: "circle")
//                                    .foregroundColor(Color.secondary.opacity(0.15))
//                                    .frame(width: 24, height: 24, alignment: .leading)
//                            )
//                    }
//                        .buttonStyle(PlainButtonStyle())
                    
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
                                    .foregroundStyle(innerCircleColor(prayer: prayer))
                                    .frame(width: 12, height: 12)
                            }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 24, height: 24, alignment: .leading)
                    
                    VStack(alignment: .leading) {
                        Text(prayer.name)
                            .font(.headline)
                        Text("\(formatTime(prayer.startTime)) - \(formatTime(prayer.endTime))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                                        
                    VStack{
                        if let engScore = prayer.englishScore, let score = prayer.numberScore, let timeAtComp = prayer.timeAtComplete  {
//                            Text("@\(shortTimePM(timeAtComp))")
//                                .font(.callout)
                            Text("\(engScore)")
                                .font(.callout)
                                .foregroundColor(innerCircleColor(prayer: prayer))
                        }
                    }

                    // Stepper for Number Score
//                    if let score = prayer.numberScore {
//                        Stepper(value: Binding<Double>(
//                            get: { prayer.numberScore ?? 0 },
//                            set: { newValue in updatePrayerScore(prayer, score: newValue) }
//                        ), in: -1...1, step: 0.1) {
//                            Text("\(String(format: "%.2f", score))")
//                                .font(.footnote)
//                        }
//                    }

                    

                }
            }
//            ScoreCarouselView()
        }
        .onAppear(perform: fetchPrayersForDate)
        .navigationTitle("Edit Prayers")
    }
    
    // Fetch prayers for the selected date
    private func fetchPrayersForDate() {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) else { return }
        
        let fetchDescriptor = FetchDescriptor<PrayerModel>(
            predicate: #Predicate<PrayerModel> {
                $0.startTime >= startOfDay && $0.startTime <= endOfDay
            },
            sortBy: [SortDescriptor(\.startTime)]
        )
        
        do {
            prayersForDate = try context.fetch(fetchDescriptor)
        } catch {
            print("❌ Failed to fetch prayers for date \(selectedDate): \(error)")
            prayersForDate = []
        }
    }
    
//    // Update a prayer's completion status
//    private func updatePrayerCompletion(_ prayer: PrayerModel) {
//        if prayer.startTime > Date() { return }
//        prayer.isCompleted.toggle()
//        prayer.numberScore = prayer.isCompleted ? 0.5 : nil
//        
//        do {
//            try context.save()
//            viewModel.calculatePrayerStreak()
//        } catch {
//            print("❌ Failed to update prayer \(prayer.name): \(error)")
//        }
//    }
    
    // Update a prayer's score
    private func updatePrayerScore(_ prayer: PrayerModel, score: Double) {
        prayer.numberScore = score <= -0.19 ? nil : score
        prayer.isCompleted = prayer.numberScore == nil ? false : true
        
        do {
            try context.save()
            viewModel.calculatePrayerStreak()
        } catch {
            print("❌ Failed to update prayer score for \(prayer.name): \(error)")
        }
    }
    
//    func setPrayerScore(for prayer: PrayerModel, atDate: Date = Date()) {
////        print("setting time at complete as: ", atDate)
//        prayer.timeAtComplete = atDate
//
//        if let completedTime = prayer.timeAtComplete {
//            let timeLeft = prayer.endTime.timeIntervalSince(completedTime)
//            let totalInterval = prayer.endTime.timeIntervalSince(prayer.startTime)
//            let score = timeLeft / totalInterval
//            prayer.numberScore = max(0, min(score, 1))
//
//            if let percentage = prayer.numberScore {
//                if percentage > 0.50 {
//                    prayer.englishScore = "Optimal"
//                } else if percentage > 0.25 {
//                    prayer.englishScore = "Good"
//                } else if percentage > 0 {
//                    prayer.englishScore = "Poor"
//                } else {
//                    prayer.englishScore = "Kaza"
//                }
//            }
//        }
//    }
    
    // Format time for display
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ScoreCarouselView: View {
    @Query private var scores: [DailyPrayerScore]
    @State private var selectedScore: DailyPrayerScore?
    
    // Configuration
    private let visibleCount: Int = 5          // How many items are visible at once
    private let itemSpacing: CGFloat = 16      // Spacing between items
    private let itemWidth: CGFloat = 70        // Fixed width for each item (adjust as needed)
    private let maxCircleHeight: CGFloat = 100 // Maximum circle height for a score of 1.0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: itemSpacing) {
                ForEach(scores) { score in
                    VStack {
                        // The circle height is proportionate to averageScore (0.0–1.0)
                        Circle()
                            .fill(selectedScore?.id == score.id ? Color.accentColor : Color.gray)
                            .frame(width: 50, height: circleHeight(for: score))
                            .scrollTargetLayout()  // Marks this view for snapping/transition animations
                            // Optionally, you can add a .scrollTransition modifier here for custom animations.
                        
                        // Display the date below the circle.
                        Text(score.date, style: .date)
                            .font(.caption)
                    }
                    .frame(width: itemWidth)
                    .id(score.id)
                }
            }
            // Use containerRelativeFrame to evenly layout items based on visible count and spacing.
            .containerRelativeFrame(.horizontal, count: visibleCount, spacing: itemSpacing)
            // Add content margins so that the first and last items can center properly.
        }
        .contentMargins(.horizontal, itemSpacing)
        // Snap each item into alignment using viewAligned behavior.
        .scrollTargetBehavior(.viewAligned)
        .frame(height: 150)
    }
    
    private func circleHeight(for score: DailyPrayerScore) -> CGFloat {
        let value = score.averageScore ?? 0
        return maxCircleHeight * CGFloat(value)
    }
}
