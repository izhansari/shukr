//
//  PrayerEditorView.swift
//  shukr
//
//  Created on 1/17/25.
//


import SwiftUI
import SwiftData

struct PrayerEditorView: View {
    @Environment(\.modelContext) private var context
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
    
    private func isFuturePrayer(for prayer: PrayerModel) -> Bool {
        prayer.startTime > Date()
    }
    
    // Status Circle Properties
    private func statusImageName(for prayer: PrayerModel) -> String {
        if isFuturePrayer(for: prayer) { return "circle" }
        return prayer.isCompleted ? "checkmark.circle.fill" : "circle"
    }
    
    private func statusColor(for prayer: PrayerModel) -> Color {
        if isFuturePrayer(for: prayer) { return Color.secondary.opacity(0.2) }
        return prayer.isCompleted ? viewModel.getColorForPrayerScore(prayer.numberScore).opacity(/*colorScheme == .dark ? 0.5 : */0.70) : Color.secondary.opacity(0.5)
    }
    
    var body: some View {
        VStack {
            HStack{
                Text("Streak: \(prayerStreak)")
                Text("Max: \(maxPrayerStreak)")
//                Text("Beg Date: \(streakBegDateString /*dateOfMaxPrayerStreak.formatted(.dateTime.day(.defaultDigits).month(.defaultDigits).year(.defaultDigits).locale(.current))*/)")
//                Text("End Date: \(streakEndDateString)")
                Text("from \(streakBegDateString) - \(streakEndDateString)")
            }
            
            // Mode Selection
            Picker("Streak Type", selection: $prayerStreakMode) {
                Text("Level 1").tag(1)
                Text("Level 2").tag(2)
                Text("Level 3").tag(3)
            }
            .pickerStyle(.segmented)
            .onChange(of: prayerStreakMode){ _, new in
                viewModel.calculatePrayerStreak()
            }

            // Date Picker
            DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .onChange(of: selectedDate) { _, new in
                    fetchPrayersForDate()
                }
            
            // List of Prayers for Selected Date
            List(prayersForDate) { prayer in
                HStack {
                    Button(action: {
                        updatePrayerCompletion(prayer)
                    }) {
                        Image(systemName: statusImageName(for: prayer))
                            .foregroundColor(statusColor(for: prayer))
                            .frame(width: 24, height: 24, alignment: .leading)
                            .overlay(
                                Image(systemName: "circle")
                                    .foregroundColor(Color.secondary.opacity(0.15))
                                    .frame(width: 24, height: 24, alignment: .leading)
                            )
                    }
                        .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading) {
                        Text(prayer.name)
                            .font(.headline)
                        Text("\(formatTime(prayer.startTime)) - \(formatTime(prayer.endTime))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                                        
                    // Stepper for Number Score
                    if let score = prayer.numberScore {
                        Stepper(value: Binding<Double>(
                            get: { prayer.numberScore ?? 0 },
                            set: { newValue in updatePrayerScore(prayer, score: newValue) }
                        ), in: -1...1, step: 0.1) {
                            Text("\(String(format: "%.2f", score))")
                                .font(.footnote)
                        }
                    }

                    

                }
            }
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
    
    // Update a prayer's completion status
    private func updatePrayerCompletion(_ prayer: PrayerModel) {
        if prayer.startTime > Date() { return }
        prayer.isCompleted.toggle()
        prayer.numberScore = prayer.isCompleted ? 0.5 : nil
        
        do {
            try context.save()
            viewModel.calculatePrayerStreak()
        } catch {
            print("❌ Failed to update prayer \(prayer.name): \(error)")
        }
    }
    
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
