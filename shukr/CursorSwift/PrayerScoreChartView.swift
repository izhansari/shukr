//
//  PrayerScoreChartView.swift
//  shukr
//
//  Created by Izhan S Ansari on 3/5/25.
//


import SwiftUI
import SwiftData
import Charts

struct PrayerScoreChartView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var viewModel: PrayerViewModel
    @Query private var scores: [DailyPrayerScore]
    
    @State private var timeRange: TimeRange = .week
    @State private var chartData: [ChartDataPoint] = []
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        case year = "Year"
        case all = "All Time"
        
        var id: String { self.rawValue }
        
        var days: Int {
            switch self {
            case .week: return 7
            case .month: return 30
            case .threeMonths: return 90
            case .year: return 365
            case .all: return 1000 // Large number to get all records
            }
        }
    }
    
    struct ChartDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Double
        
        var scorePercentage: Double {
            score * 100
        }
    }
    
    // Add this function to PrayerScoreChartView
    private func processPast30DaysData() {
        let today = Date()
        let calendar = Calendar.current
        
        // Process last 30 days
        for dayOffset in 0..<30 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            viewModel.calculateDayScore(for: date)
        }
        
        // Reload chart data
        loadData()
    }
    
    var body: some View {
        
            VStack {
                // Time range selector
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Chart
                if chartData.isEmpty {
                    ContentUnavailableView {
                        Label("No Prayer Score Data", systemImage: "chart.line.downtrend.xyaxis")
                    } description: {
                        Text("Complete prayers to see your progress over time.")
                    }
                } else {
                    Chart {
                        ForEach(chartData) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Score", point.scorePercentage)
                            )
                            .foregroundStyle(Color.green.gradient)
                            .symbol {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        
                        RuleMark(y: .value("Optimal", 90))
                            .foregroundStyle(Color.green.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .leading) {
                                Text("Optimal")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        
                        RuleMark(y: .value("Good", 75))
                            .foregroundStyle(Color.yellow.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .leading) {
                                Text("Good")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        
                        RuleMark(y: .value("Poor", 50))
                            .foregroundStyle(Color.red.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .annotation(position: .leading) {
                                Text("Poor")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                    }
                    .chartXAxis {
                        AxisMarks(preset: .aligned, values: getAxisValues()) { value in
                            if let date = value.as(Date.self) {
                                let formatter = dateFormatter(for: timeRange)
                                AxisValueLabel(formatter.string(from: date))
                                    .font(.caption2)
                            }
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let doubleValue = value.as(Double.self) {
                                    Text("\(Int(doubleValue))%")
                                }
                            }
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 300)
                    .padding()
                    
                    // Stats summary
                    if !chartData.isEmpty {
                        HStack(spacing: 20) {
                            StatView(
                                title: "Average",
                                value: String(format: "%.1f%%", calculateAverage())
                            )
                            
                            StatView(
                                title: "Highest",
                                value: String(format: "%.1f%%", calculateHighest())
                            )
                            
                            StatView(
                                title: "Lowest",
                                value: String(format: "%.1f%%", calculateLowest())
                            )
                        }
                        .padding()
                    }
                }
                
                Spacer()
                // Add this button to your PrayerScoreChartView
                Button("Process Last 30 Days") {
                    processPast30DaysData()
                }
                .padding()
                .buttonStyle(.borderedProminent)
                .tint(.blue)


            }
            .navigationTitle("Prayer Scores")
            .onAppear {
                loadData()
            }
            .onChange(of: timeRange) { _, _ in
                loadData()
            }
        
    }
    
    // Custom function to determine which dates to show as axis marks
    private func getAxisValues() -> [Date] {
        let calendar = Calendar.current
        let today = Date()
        let startDate = calendar.date(byAdding: .day, value: -timeRange.days, to: today)!
        
        var dates: [Date] = []
        
        switch timeRange {
        case .week:
            // Show all days
            for day in 0..<7 {
                if let date = calendar.date(byAdding: .day, value: day, to: startDate) {
                    dates.append(date)
                }
            }
        case .month:
            // Show only every 5th day
            for day in stride(from: 0, to: 30, by: 5) {
                if let date = calendar.date(byAdding: .day, value: day, to: startDate) {
                    dates.append(date)
                }
            }
        case .threeMonths:
            // Show weekly dates
            for week in 0..<13 {
                if let date = calendar.date(byAdding: .weekOfYear, value: week, to: startDate) {
                    dates.append(date)
                }
            }
        case .year, .all:
            // Show monthly dates
            for month in 0..<12 {
                if let date = calendar.date(byAdding: .month, value: month, to: startDate) {
                    dates.append(date)
                }
            }
        }
        
        return dates
    }
    
    // Add this helper function to create appropriate date formatters based on the time range
    private func dateFormatter(for range: TimeRange) -> DateFormatter {
        let formatter = DateFormatter()
        
        switch range {
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            // For month view, only show every few days to avoid crowding
            formatter.dateFormat = "d"
        case .threeMonths:
            formatter.dateFormat = "MMM d"
        case .year, .all:
            formatter.dateFormat = "MMM"
        }
        
        return formatter
    }
    
    private func loadData() {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: endDate) ?? endDate
        
        // Filter scores by date range
        var filteredScores = scores.filter { score in
            let scoreDate = score.date
            return scoreDate >= startDate && scoreDate <= endDate
        }
        
        // Sort by date
        filteredScores.sort { $0.date < $1.date }
        
        // Convert to chart data
        chartData = filteredScores.compactMap { score in
            guard let scoreValue = score.averageScore else { return nil }
            return ChartDataPoint(date: score.date, score: scoreValue)
        }
    }
    
    // Update the getStrideBy function to better space the marks
    private func getStrideBy() -> Calendar.Component {
        switch timeRange {
        case .week:
            return .day
        case .month:
            return .weekOfYear  // Show weekly marks instead of daily
        case .threeMonths:
            return .weekOfYear
        case .year:
            return .month
        case .all:
            return .month
        }
    }
    
    private func calculateAverage() -> Double {
        guard !chartData.isEmpty else { return 0.0 }
        let sum = chartData.reduce(0.0) { $0 + $1.scorePercentage }
        return sum / Double(chartData.count)
    }
    
    private func calculateHighest() -> Double {
        chartData.map { $0.scorePercentage }.max() ?? 0.0
    }
    
    private func calculateLowest() -> Double {
        chartData.map { $0.scorePercentage }.filter { $0 > 0 }.min() ?? 0.0
    }
}

// Helper view for displaying statistics
struct StatView_old: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// Preview
#Preview {
    PrayerScoreChartView()
        .modelContainer(for: DailyPrayerScore.self, inMemory: true)
}



//ScrollablePrayerScoreView THE GOOD ONE
import SwiftUI
import SwiftData
import Charts


    struct ScrollablePrayerScoreView: View {
        @Environment(\.modelContext) private var context
        @EnvironmentObject var viewModel: PrayerViewModel
        @Query private var scores: [DailyPrayerScore]
        
        @State private var selectedMode: ViewMode = .daily
        @State private var selectedDate: Date = Date()
        @State private var scrollOffset: CGFloat = 0
        
        private let calendar = Calendar.current
        
        enum ViewMode: String, CaseIterable, Identifiable {
            case daily = "Daily"
            case weekly = "Weekly"
            case monthly = "Monthly"
            
            var id: String { self.rawValue }
        }
        
        struct ChartDataPoint: Identifiable {
            let id = UUID()
            let date: Date
            let score: Double?
            let isSelected: Bool
        }
        
        var body: some View {
            VStack(spacing: 0) {
                // Mode selector
                Picker("View Mode", selection: $selectedMode) {
                    Text("Daily").tag(ViewMode.daily)
                    Text("Weekly").tag(ViewMode.weekly)
                    Text("Monthly").tag(ViewMode.monthly)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .padding(.top)
                .onChange(of: selectedMode) { _, _ in
                    // Reset to current period when changing modes
                    selectedDate = Date()
                }
                
                // Header: Score display
                Text(getDisplayScore())
                    .font(.system(size: 42, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                // Chart area
                GeometryReader { geometry in
                    let chartWidth = geometry.size.width * 1 // Make chart 3x screen width
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            // Chart
                            makeChart(width: chartWidth)
                                .frame(width: chartWidth)
                                .frame(height: 200)
                                .padding(.top, 30)
                                
                            // Current date indicator (vertical line)
                            if let currentDayPosition = getCurrentDayPosition(chartWidth: chartWidth) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 1, height: 200)
                                    .offset(x: currentDayPosition)
                                    .padding(.top, 30)
                            }
                        }
                        .frame(height: 200)
                    }
                    .onAppear {
                        // Scroll to current date initially
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let position = getCurrentDayPosition(chartWidth: chartWidth) {
                                withAnimation {
                                    scrollOffset = max(0, position - geometry.size.width / 2)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedMode) { _, _ in
                        // Reset scroll when changing modes
                        if let position = getCurrentDayPosition(chartWidth: chartWidth) {
                            withAnimation {
                                scrollOffset = max(0, position - geometry.size.width / 2)
                            }
                        }
                    }
                }
                .frame(height: 250)
                
                // Date label
                Text(formatDateRange())
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 10)
                
                // Stats section
                statsSection()
                    .padding(.top, 10)
                
                Spacer()
                
                // Process button
                Button("Process Last 100 Days") {
                    processPastDaysData(days: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.blue)
                .padding()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Prayer Scores")
        }
        
        // MARK: - Chart Creation
        
        @ViewBuilder
        private func makeChart(width: CGFloat) -> some View {
            let dataPoints = generateDataPoints()
            
            if dataPoints.isEmpty {
                Text("No data available")
                    .frame(width: width)
                    .foregroundColor(.gray)
            } else {
                Chart {
                    ForEach(dataPoints) { point in
                        if let score = point.score {
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Score", score * 100)
                            )
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Score", score * 100)
                            )
                            .foregroundStyle(point.isSelected ? Color(.systemGreen) : .white)
                            .symbolSize(point.isSelected ? 30 : 8)
                        }
                    }
                    
                    // Reference lines
                    RuleMark(y: .value("Optimal", 90))
                        .foregroundStyle(Color.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    RuleMark(y: .value("Good", 75))
                        .foregroundStyle(Color.yellow.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    RuleMark(y: .value("Poor", 50))
                        .foregroundStyle(Color.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                }
                .frame(width: 300)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: getXAxisStride())) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                makeAxisLabel(for: date)
                            }
                            
                            AxisGridLine()
                                .foregroundStyle(Color.gray.opacity(0.3))
                            
                            AxisTick()
                                .foregroundStyle(Color.gray.opacity(0.3))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 75, 90, 100]) { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text("\(Int(doubleValue))%")
                                    .foregroundColor(.gray)
                                    .font(.caption2)
                            }
                        }
                        
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.3))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let xPosition = value.location.x
                                        if let date = proxy.value(atX: xPosition, as: Date.self) {
                                            selectedDate = findClosestDate(to: date, in: dataPoints)
                                        }
                                    }
                            )
                    }
                }
            }
        }
        
        // MARK: - Helper Views
        
        @ViewBuilder
        private func makeAxisLabel(for date: Date) -> some View {
            switch selectedMode {
            case .daily:
                if isFirstOfMonth(date) {
                    Text(formatMonth(date))
                        .foregroundColor(.gray)
                        .font(.caption2)
                } else {
                    Text(formatDay(date))
                        .foregroundColor(.gray)
                        .font(.caption2)
                }
            case .weekly:
                if isFirstWeekOfMonth(date) {
                    Text(formatMonth(date))
                        .foregroundColor(.gray)
                        .font(.caption2)
                } else {
                    Text("\(getWeekNumber(date))")
                        .foregroundColor(.gray)
                        .font(.caption2)
                }
            case .monthly:
                Text(formatMonth(date))
                    .foregroundColor(.gray)
                    .font(.caption2)
            }
        }
        
        @ViewBuilder
        private func statsSection() -> some View {
            let stats = getStatsForSelectedPeriod()
            
            switch selectedMode {
            case .daily:
                // For daily, show just a single stat
                if let score = stats.average {
                    HStack {
                        StatView(
                            title: "Score",
                            value: String(format: "%.1f%%", score * 100)
                        )
                    }
                    .padding(.horizontal)
                }
            case .weekly, .monthly:
                // For weekly and monthly, show average, highest, lowest
                HStack(spacing: 20) {
                    if let avg = stats.average {
                        StatView(
                            title: "Average",
                            value: String(format: "%.1f%%", avg * 100)
                        )
                    }
                    
                    if let high = stats.highest {
                        StatView(
                            title: "Highest",
                            value: String(format: "%.1f%%", high * 100)
                        )
                    }
                    
                    if let low = stats.lowest {
                        StatView(
                            title: "Lowest",
                            value: String(format: "%.1f%%", low * 100)
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
        
        // MARK: - Helper Functions
        
        private func getDisplayScore() -> String {
            if let score = getScoreForSelectedPeriod() {
                return "\(Int(score * 100))%"
            } else {
                return "0%"
            }
        }
        
        private func getCurrentDayPosition(chartWidth: CGFloat) -> CGFloat? {
            let dataPoints = generateDataPoints()
            guard !dataPoints.isEmpty else { return nil }
            
            // Find today's index
            let today = selectedDate
            if let todayIndex = dataPoints.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
                let totalPoints = CGFloat(dataPoints.count)
                return (CGFloat(todayIndex) / totalPoints) * chartWidth
            }
            return nil
        }
        
        private func getXAxisStride() -> Calendar.Component {
            switch selectedMode {
            case .daily:
                return .day
            case .weekly:
                return .weekOfYear
            case .monthly:
                return .month
            }
        }
        
        // MARK: - Data Generation
        
        private func generateDataPoints() -> [ChartDataPoint] {
            let today = Date()
            var dates: [Date] = []
            var result: [ChartDataPoint] = []
            
            // Generate dates based on view mode
            switch selectedMode {
            case .daily:
                // Generate days range
                for dayOffset in -60..<30 {
                    if let date = calendar.date(byAdding: .day, value: dayOffset, to: today) {
                        dates.append(calendar.startOfDay(for: date))
                    }
                }
            case .weekly:
                // Generate weeks range
                for weekOffset in -24..<12 {
                    if let date = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today) {
                        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
                        dates.append(weekStart)
                    }
                }
            case .monthly:
                // Generate months range
                for monthOffset in -24..<12 {
                    if let date = calendar.date(byAdding: .month, value: monthOffset, to: today) {
                        let components = calendar.dateComponents([.year, .month], from: date)
                        let monthStart = calendar.date(from: components)!
                        dates.append(monthStart)
                    }
                }
            }
            
            // Sort dates chronologically
            dates.sort()
            
            // Create chart data points
            for date in dates {
                let score = getScoreForDate(date)
                let isSelected = calendar.isDate(date, equalTo: selectedDate, toGranularity: getGranularity())
                
                result.append(ChartDataPoint(
                    date: date,
                    score: score,
                    isSelected: isSelected
                ))
            }
            
            return result
        }
        
        // MARK: - Score Calculation
        
        private func getScoreForDate(_ date: Date) -> Double? {
            switch selectedMode {
            case .daily:
                return getDailyScore(for: date)
            case .weekly:
                return getWeeklyScore(for: date)
            case .monthly:
                return getMonthlyScore(for: date)
            }
        }
        
        private func getDailyScore(for date: Date) -> Double? {
            let startOfDay = calendar.startOfDay(for: date)
            
            let dailyScore = scores.first { score in
                calendar.isDate(score.date, inSameDayAs: startOfDay)
            }
            
            return dailyScore?.averageScore
        }
        
        private func getWeeklyScore(for weekStart: Date) -> Double? {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            
            let weekScores = scores.filter { score in
                score.date >= weekStart && score.date <= weekEnd
            }.compactMap { $0.averageScore }
            
            guard !weekScores.isEmpty else { return nil }
            return weekScores.reduce(0, +) / Double(weekScores.count)
        }
        
        private func getMonthlyScore(for monthStart: Date) -> Double? {
            var components = DateComponents()
            components.month = 1
            components.day = -1
            let monthEnd = calendar.date(byAdding: components, to: monthStart)!
            
            let monthScores = scores.filter { score in
                score.date >= monthStart && score.date <= monthEnd
            }.compactMap { $0.averageScore }
            
            guard !monthScores.isEmpty else { return nil }
            return monthScores.reduce(0, +) / Double(monthScores.count)
        }
        
        private func getScoreForSelectedPeriod() -> Double? {
            return getScoreForDate(selectedDate)
        }
        
        private func getStatsForSelectedPeriod() -> (average: Double?, highest: Double?, lowest: Double?) {
            switch selectedMode {
            case .daily:
                let score = getDailyScore(for: selectedDate)
                return (score, score, score)
                
            case .weekly:
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: selectedDate)!
                
                let weekScores = scores.filter { score in
                    score.date >= selectedDate && score.date <= weekEnd
                }.compactMap { $0.averageScore }
                
                guard !weekScores.isEmpty else { return (nil, nil, nil) }
                
                let average = weekScores.reduce(0, +) / Double(weekScores.count)
                let highest = weekScores.max()
                let lowest = weekScores.min()
                
                return (average, highest, lowest)
                
            case .monthly:
                var components = DateComponents()
                components.month = 1
                components.day = -1
                let monthEnd = calendar.date(byAdding: components, to: selectedDate)!
                
                let monthScores = scores.filter { score in
                    score.date >= selectedDate && score.date <= monthEnd
                }.compactMap { $0.averageScore }
                
                guard !monthScores.isEmpty else { return (nil, nil, nil) }
                
                let average = monthScores.reduce(0, +) / Double(monthScores.count)
                let highest = monthScores.max()
                let lowest = monthScores.min()
                
                return (average, highest, lowest)
            }
        }
        
        // MARK: - Formatting Functions
        
        private func formatDateRange() -> String {
            let formatter = DateFormatter()
            
            switch selectedMode {
            case .daily:
                formatter.dateFormat = "MMMM d, yyyy"
                return formatter.string(from: selectedDate)
                
            case .weekly:
                let weekEnd = calendar.date(byAdding: .day, value: 6, to: selectedDate)!
                
                formatter.dateFormat = "MMM d"
                let startString = formatter.string(from: selectedDate)
                
                formatter.dateFormat = "MMM d, yyyy"
                let endString = formatter.string(from: weekEnd)
                
                return "\(startString) – \(endString)"
                
            case .monthly:
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: selectedDate)
            }
        }
        
        private func formatDay(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "d"
            return formatter.string(from: date)
        }
        
        private func formatMonth(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
        
        private func isFirstOfMonth(_ date: Date) -> Bool {
            let components = calendar.dateComponents([.day], from: date)
            return components.day == 1
        }
        
        private func isFirstWeekOfMonth(_ date: Date) -> Bool {
            let components = calendar.dateComponents([.weekOfMonth], from: date)
            return components.weekOfMonth == 1
        }
        
        private func getWeekNumber(_ date: Date) -> Int {
            let components = calendar.dateComponents([.weekOfYear], from: date)
            return components.weekOfYear ?? 0
        }
        
        private func findClosestDate(to date: Date, in dataPoints: [ChartDataPoint]) -> Date {
            guard let closest = dataPoints.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }) else {
                return date
            }
            return closest.date
        }
        
        private func getGranularity() -> Calendar.Component {
            switch selectedMode {
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
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

    // Helper view for displaying statistics
    struct StatView: View {
        let title: String
        let value: String
        
        var body: some View {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        }
    }

    #Preview {
        NavigationView {
            ScrollablePrayerScoreView()
                .modelContainer(for: DailyPrayerScore.self, inMemory: true)
        }
    }




/*
 import SwiftUI
import SwiftData
import Charts

struct ScrollablePrayerScoreView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var viewModel: PrayerViewModel
    @Query private var scores: [DailyPrayerScore]
    
    @State private var selectedMode: ViewMode = .daily
    @State private var selectedIndex: Int = 0
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var scrollViewWidth: CGFloat = 0
    
    enum ViewMode: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekly = "Weekly"
        case monthly = "Monthly"
        
        var id: String { self.rawValue }
    }
    
    struct ChartDataPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let score: Double?
        let formattedLabel: String
        
        static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
            return Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mode selector
            Picker("View Mode", selection: $selectedMode) {
                Text("Daily").tag(ViewMode.daily)
                Text("Weekly").tag(ViewMode.weekly)
                Text("Monthly").tag(ViewMode.monthly)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top)
            .onChange(of: selectedMode) { _, _ in
                // Reset and regenerate data when mode changes
                generateDataPoints()
                scrollToToday()
            }
            
            // Header: Score display
            if let score = selectedDataPoint?.score {
                Text("\(Int(score * 100))%")
                    .font(.system(size: 42, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
            } else {
                Text("0%")
                    .font(.system(size: 42, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
            }
            
            // Chart area
            chartView()
                .frame(height: 250)
                .padding(.top, 20)
            
            // Carousel selector
            carouselSelector()
                .padding(.top, 10)
            
            // Date label
            Text(formatSelectedDate())
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 20)
            
            // Stats section
            statsSection()
                .padding(.top, 10)
            
            Spacer()
            
            // Process button
            Button("Process Last 100 Days") {
                processPastDaysData(days: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.blue)
            .padding()
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Prayer Scores")
        .onAppear {
            generateDataPoints()
            scrollToToday()
        }
    }
    
    // MARK: - Chart View
    
    @ViewBuilder
    private func chartView() -> some View {
        VStack {
            if dataPoints.isEmpty {
                Text("No data available")
                    .foregroundColor(.gray)
                    .frame(height: 200)
            } else {
                Chart {
                    // Reference lines
                    RuleMark(y: .value("Optimal", 90))
                        .foregroundStyle(Color.green.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    RuleMark(y: .value("Good", 75))
                        .foregroundStyle(Color.yellow.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    RuleMark(y: .value("Poor", 50))
                        .foregroundStyle(Color.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    // Data lines and points
                    ForEach(visibleDataPoints) { point in
                        if let score = point.score {
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Score", score * 100)
                            )
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            
                            if point == selectedDataPoint {
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Score", score * 100)
                                )
                                .foregroundStyle(.yellow)
                                .symbolSize(14)
                            } else {
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Score", score * 100)
                                )
                                .foregroundStyle(.white)
                                .symbolSize(8)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: getXAxisStride())) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(formatAxisDate(date))
                                    .foregroundColor(.gray)
                                    .font(.caption2)
                            }
                            
                            AxisGridLine()
                                .foregroundStyle(Color.gray.opacity(0.3))
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 75, 90, 100]) { value in
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text("\(Int(doubleValue))%")
                                    .foregroundColor(.gray)
                                    .font(.caption2)
                            }
                        }
                        
                        AxisGridLine()
                            .foregroundStyle(Color.gray.opacity(0.3))
                    }
                }
            }
        }
    }
    
    // MARK: - Carousel Selector
    
    @ViewBuilder
    private func carouselSelector() -> some View {
        GeometryReader { geometry in
            let itemWidth: CGFloat = 60
            let spacing: CGFloat = 10
            let totalWidth = geometry.size.width
            
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, point in
                            VStack(spacing: 2) {
                                // Day indicator
                                Text(point.formattedLabel)
                                    .font(.caption2)
                                    .foregroundColor(index == selectedIndex ? .white : .gray)
                                
                                // Score indicator dot
                                if let score = point.score {
                                    Circle()
                                        .fill(getScoreColor(score: score))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .frame(width: itemWidth)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(index == selectedIndex ? Color.gray.opacity(0.3) : Color.clear)
                            )
                            .id(index)
                            .onTapGesture {
                                withAnimation {
                                    selectedIndex = index
                                }
                            }
                        }
                    }
                    .padding(.horizontal, (totalWidth - itemWidth) / 2)
                    .onAppear {
                        // Save scroll view width for calculations
                        scrollViewWidth = totalWidth
                    }
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    // Scroll to keep the selected item centered
                    withAnimation {
                        scrollProxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            .frame(height: 40)
        }
        .frame(height: 40)
    }
    
    @ViewBuilder
    private func statsSection() -> some View {
        let stats = getStatsForSelectedPeriod()
        
        switch selectedMode {
        case .daily:
            // For daily, show just a single stat
            if let score = stats.average {
                HStack {
                    StatView(
                        title: "Score",
                        value: String(format: "%.1f%%", score * 100)
                    )
                }
                .padding(.horizontal)
            }
        case .weekly, .monthly:
            // For weekly and monthly, show average, highest, lowest
            HStack(spacing: 20) {
                if let avg = stats.average {
                    StatView(
                        title: "Average",
                        value: String(format: "%.1f%%", avg * 100)
                    )
                }
                
                if let high = stats.highest {
                    StatView(
                        title: "Highest",
                        value: String(format: "%.1f%%", high * 100)
                    )
                }
                
                if let low = stats.lowest {
                    StatView(
                        title: "Lowest",
                        value: String(format: "%.1f%%", low * 100)
                    )
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Data Management
    
    private var selectedDataPoint: ChartDataPoint? {
        guard selectedIndex >= 0 && selectedIndex < dataPoints.count else {
            return nil
        }
        return dataPoints[selectedIndex]
    }
    
    private var visibleDataPoints: [ChartDataPoint] {
        // Show a window of data points around the selected index
        let windowSize = 15 // Points on each side
        let startIndex = max(0, selectedIndex - windowSize)
        let endIndex = min(dataPoints.count - 1, selectedIndex + windowSize)
        
        guard startIndex <= endIndex else { return [] }
        return Array(dataPoints[startIndex...endIndex])
    }
    
    private func generateDataPoints() {
        let calendar = Calendar.current
        let today = Date()
        var points: [ChartDataPoint] = []
        
        switch selectedMode {
        case .daily:
            // Last 90 days to next 30 days
            for dayOffset in -90..<30 {
                if let date = calendar.date(byAdding: .day, value: dayOffset, to: today) {
                    let dayStart = calendar.startOfDay(for: date)
                    let score = getDailyScore(for: dayStart)
                    
                    let dayFormatter = DateFormatter()
                    dayFormatter.dateFormat = "d"
                    let formattedDay = dayFormatter.string(from: dayStart)
                    
                    points.append(ChartDataPoint(
                        date: dayStart,
                        score: score,
                        formattedLabel: formattedDay
                    ))
                }
            }
            
        case .weekly:
            // Last 52 weeks to next 12 weeks
            for weekOffset in -52..<12 {
                if let date = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today) {
                    let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
                    let score = getWeeklyScore(for: weekStart)
                    
                    let weekFormatter = DateFormatter()
                    weekFormatter.dateFormat = "W"
                    let formattedWeek = weekFormatter.string(from: weekStart)
                    
                    points.append(ChartDataPoint(
                        date: weekStart,
                        score: score,
                        formattedLabel: formattedWeek
                    ))
                }
            }
            
        case .monthly:
            // Last 24 months to next 12 months
            for monthOffset in -24..<12 {
                if let date = calendar.date(byAdding: .month, value: monthOffset, to: today) {
                    let components = calendar.dateComponents([.year, .month], from: date)
                    let monthStart = calendar.date(from: components)!
                    let score = getMonthlyScore(for: monthStart)
                    
                    let monthFormatter = DateFormatter()
                    monthFormatter.dateFormat = "MMM"
                    let formattedMonth = monthFormatter.string(from: monthStart)
                    
                    points.append(ChartDataPoint(
                        date: monthStart,
                        score: score,
                        formattedLabel: formattedMonth
                    ))
                }
            }
        }
        
        dataPoints = points
    }
    
    private func scrollToToday() {
        // Find today's index and select it
        let calendar = Calendar.current
        let today = Date()
        
        if let todayIndex = dataPoints.firstIndex(where: { point in
            switch selectedMode {
            case .daily:
                return calendar.isDate(point.date, inSameDayAs: today)
            case .weekly:
                let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
                return calendar.isDate(point.date, inSameDayAs: thisWeekStart)
            case .monthly:
                let thisMonthComponents = calendar.dateComponents([.year, .month], from: today)
                let thisMonthStart = calendar.date(from: thisMonthComponents)!
                return calendar.isDate(point.date, inSameDayAs: thisMonthStart)
            }
        }) {
            selectedIndex = todayIndex
        } else if !dataPoints.isEmpty {
            // If today not found, select the most recent data point
            selectedIndex = dataPoints.count - 1
        }
    }
    
    // MARK: - Score Calculations
    
    private func getDailyScore(for date: Date) -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        let dailyScore = scores.first { score in
            calendar.isDate(score.date, inSameDayAs: startOfDay)
        }
        
        return dailyScore?.averageScore
    }
    
    private func getWeeklyScore(for weekStart: Date) -> Double? {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        
        let weekScores = scores.filter { score in
            score.date >= weekStart && score.date <= weekEnd
        }.compactMap { $0.averageScore }
        
        guard !weekScores.isEmpty else { return nil }
        return weekScores.reduce(0, +) / Double(weekScores.count)
    }
    
    private func getMonthlyScore(for monthStart: Date) -> Double? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.month = 1
        components.day = -1
        let monthEnd = calendar.date(byAdding: components, to: monthStart)!
        
        let monthScores = scores.filter { score in
            score.date >= monthStart && score.date <= monthEnd
        }.compactMap { $0.averageScore }
        
        guard !monthScores.isEmpty else { return nil }
        return monthScores.reduce(0, +) / Double(monthScores.count)
    }
    
    private func getStatsForSelectedPeriod() -> (average: Double?, highest: Double?, lowest: Double?) {
        guard let point = selectedDataPoint else {
            return (nil, nil, nil)
        }
        
        let calendar = Calendar.current
        
        switch selectedMode {
        case .daily:
            return (point.score, point.score, point.score)
            
        case .weekly:
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: point.date)!
            
            let weekScores = scores.filter { score in
                score.date >= point.date && score.date <= weekEnd
            }.compactMap { $0.averageScore }
            
            guard !weekScores.isEmpty else { return (nil, nil, nil) }
            
            let average = weekScores.reduce(0, +) / Double(weekScores.count)
            let highest = weekScores.max()
            let lowest = weekScores.min()
            
            return (average, highest, lowest)
            
        case .monthly:
            var components = DateComponents()
            components.month = 1
            components.day = -1
            let monthEnd = calendar.date(byAdding: components, to: point.date)!
            
            let monthScores = scores.filter { score in
                score.date >= point.date && score.date <= monthEnd
            }.compactMap { $0.averageScore }
            
            guard !monthScores.isEmpty else { return (nil, nil, nil) }
            
            let average = monthScores.reduce(0, +) / Double(monthScores.count)
            let highest = monthScores.max()
            let lowest = monthScores.min()
            
            return (average, highest, lowest)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatSelectedDate() -> String {
        guard let point = selectedDataPoint else {
            return ""
        }
        
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        switch selectedMode {
        case .daily:
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: point.date)
            
        case .weekly:
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: point.date)!
            
            formatter.dateFormat = "MMM d"
            let startString = formatter.string(from: point.date)
            
            formatter.dateFormat = "MMM d, yyyy"
            let endString = formatter.string(from: weekEnd)
            
            return "\(startString) – \(endString)"
            
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: point.date)
        }
    }
    
    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        switch selectedMode {
        case .daily:
            formatter.dateFormat = "d"
            return formatter.string(from: date)
        case .weekly:
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        case .monthly:
            formatter.dateFormat = "MMM"
            return formatter.string(from: date)
        }
    }
    
    private func getXAxisStride() -> Calendar.Component {
        switch selectedMode {
        case .daily:
            return .day
        case .weekly:
            return .weekOfYear
        case .monthly:
            return .month
        }
    }
    
    private func getScoreColor(score: Double) -> Color {
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
    
    private func processPastDaysData(days: Int) {
        let today = Date()
        let calendar = Calendar.current
        
        // Process past days
        for dayOffset in 0..<days {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            viewModel.calculateDayScore(for: date)
        }
        
        // Regenerate data points with the new data
        generateDataPoints()
        scrollToToday()
    }
}

// Helper view for displaying statistics
struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationView {
        ScrollablePrayerScoreView()
            .modelContainer(for: DailyPrayerScore.self, inMemory: true)
    }
}
*/


/*
import SwiftUI
import SwiftData
import Charts

struct ScrollablePrayerScoreView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var viewModel: PrayerViewModel
    @Query private var scores: [DailyPrayerScore]
    
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var selectedIndex: Int = 0
    @State private var scrollOffset = CGPoint.zero
    @State private var chartWidth: CGFloat = 0
    
    // Constants for layout
    private let pointSpacing: CGFloat = 30
    private let calendar = Calendar.current
    
    struct ChartDataPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let score: Double?
        
        static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
            return Calendar.current.isDate(lhs.date, inSameDayAs: rhs.date)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mode selector placeholder - we'll focus just on Daily for now
            Picker("View Mode", selection: .constant(0)) {
                Text("Daily").tag(0)
                Text("Weekly").tag(1)
                Text("Monthly").tag(2)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top)
            
            // Header: Score display
            if let score = selectedDataPoint?.score {
                Text("\(Int(score * 100))%")
                    .font(.system(size: 42, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
            } else {
                Text("0%")
                    .font(.system(size: 42, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
            }
            
            // Chart area
            GeometryReader { geometry in
                let fullChartWidth = CGFloat(dataPoints.count) * pointSpacing
                let screenWidth = geometry.size.width
                
                // Make chart at least 3x screen width or fit all points
                let finalChartWidth = max(screenWidth * 3, fullChartWidth)
            
                
                ZStack(alignment: .top) {
                    // Reference lines
                    VStack(spacing: 0) {
                        Divider().background(Color.green.opacity(0.5))
                            .offset(y: geometry.size.height * 0.1) // 90%
                        
                        Divider().background(Color.yellow.opacity(0.5))
                            .offset(y: geometry.size.height * 0.25) // 75%
                        
                        Divider().background(Color.red.opacity(0.5))
                            .offset(y: geometry.size.height * 0.5) // 50%
                    }
                    .frame(width: finalChartWidth)
                    
                    // Scrollable chart
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollViewReader { proxy in
                            ZStack {
                                // Chart content
                                chartContent(width: finalChartWidth, height: geometry.size.height)
                                    .frame(width: finalChartWidth, height: geometry.size.height)
                                
                                // Center line indicator (fixed in the middle)
                                Rectangle()
                                    .fill(Color.white.opacity(0.3))
                                    .frame(width: 2, height: geometry.size.height)
                                    .position(x: screenWidth / 2, y: geometry.size.height / 2)
                                    .allowsHitTesting(false)
                            }
                            .onChange(of: selectedIndex) { _, newIndex in
                                withAnimation {
                                    // Calculate the target scroll position
                                    let targetPosition = CGFloat(newIndex) * pointSpacing
                                    let centeredPosition = targetPosition - (screenWidth / 2) + (pointSpacing / 2)
                                    
                                    // Scroll programmatically to keep the selected point centered
                                    proxy.scrollTo("point-\(newIndex)", anchor: .center)
                                }
                            }
                            .onAppear {
                                // Initial scroll to today
                                if let todayIndex = findTodayIndex() {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        withAnimation {
                                            selectedIndex = todayIndex
                                        }
                                    }
                                }
                            }
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        // Update during drag to find the new selected index
                                        let currentScrollPosition = value.location.x
                                        let newIndex = Int(round((currentScrollPosition - pointSpacing/2) / pointSpacing))
                                        if newIndex >= 0 && newIndex < dataPoints.count && newIndex != selectedIndex {
                                            selectedIndex = newIndex
                                        }
                                    }
                            )
                        }
                    }
                    .scrollDisabled(dataPoints.isEmpty)
                }
                // Store the chart width for reference
                .onAppear {
                    chartWidth = finalChartWidth
                }
                .onChange(of: dataPoints.count) { _, _ in
                    chartWidth = finalChartWidth
                }
            }
            .frame(height: 250)
            .padding(.top, 20)
            
            // Date label
            Text(formatSelectedDate())
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 10)
            
            // Stats section
            statsSection()
                .padding(.top, 10)
            
            Spacer()
            
            // Process button
            Button("Process Last 100 Days") {
                processPastDaysData(days: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.blue)
            .padding()
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Prayer Scores")
        .onAppear {
            generateDataPoints()
        }
    }
    
    // MARK: - Chart Content
    
    @ViewBuilder
    private func chartContent(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if dataPoints.isEmpty {
                Text("No data available")
                    .foregroundColor(.gray)
                    .frame(width: width, height: height)
            } else {
                // Canvas for custom chart drawing
                Canvas { context, size in
                    // Draw lines connecting points
                    drawChartLines(context: context, size: size)
                    
                    // Draw data points
                    drawChartPoints(context: context, size: size)
                }
                .frame(width: width, height: height)
                
                // Add interactive hit targets for each point
                HStack(spacing: pointSpacing - 10) {
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, point in
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 30, height: 30)
                            .id("point-\(index)")
                            .onTapGesture {
                                withAnimation {
                                    selectedIndex = index
                                }
                            }
                    }
                }
                .frame(height: height)
                .padding(.horizontal, 5)
                .allowsHitTesting(true)
            }
        }
    }
    
    private func drawChartLines(context: GraphicsContext, size: CGSize) {
        var path = Path()
        let pointCount = dataPoints.count
        
        // Map score to y position (0% at bottom, 100% at top)
        func yPosition(for score: Double?) -> CGFloat {
            guard let score = score else { return size.height } // No score = bottom
            // Invert the y-axis (0 at top in graphics context)
            return size.height - (CGFloat(score) * size.height)
        }
        
        // Draw connecting lines
        var firstPoint = true
        
        for i in 0..<pointCount {
            let point = dataPoints[i]
            let xPos = CGFloat(i) * pointSpacing + (pointSpacing / 2)
            let yPos = yPosition(for: point.score)
            
            if firstPoint, let _ = point.score {
                path.move(to: CGPoint(x: xPos, y: yPos))
                firstPoint = false
            } else if let _ = point.score {
                path.addLine(to: CGPoint(x: xPos, y: yPos))
            } else {
                firstPoint = true
            }
        }
        
        // Draw the path
        context.stroke(path, with: .color(.white), lineWidth: 2)
    }
    
    private func drawChartPoints(context: GraphicsContext, size: CGSize) {
        for i in 0..<dataPoints.count {
            let point = dataPoints[i]
            guard let score = point.score else { continue }
            
            let xPos = CGFloat(i) * pointSpacing + (pointSpacing / 2)
            let yPos = size.height - (CGFloat(score) * size.height)
            
            let isSelected = i == selectedIndex
            let pointSize: CGFloat = isSelected ? 10 : 6
            let pointColor: Color = isSelected ? .yellow : .white
            
            let circle = Path(ellipseIn: CGRect(
                x: xPos - pointSize/2,
                y: yPos - pointSize/2,
                width: pointSize,
                height: pointSize
            ))
            
            context.fill(circle, with: .color(pointColor))
        }
    }
    
    // MARK: - Stats Section
    
    @ViewBuilder
    private func statsSection() -> some View {
        if let score = selectedDataPoint?.score {
            HStack {
                StatView(
                    title: "Score",
                    value: String(format: "%.1f%%", score * 100)
                )
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Data Management
    
    private var selectedDataPoint: ChartDataPoint? {
        guard selectedIndex >= 0 && selectedIndex < dataPoints.count else {
            return nil
        }
        return dataPoints[selectedIndex]
    }
    
    private func generateDataPoints() {
        let today = Date()
        var points: [ChartDataPoint] = []
        
        // Last 90 days to next 30 days
        for dayOffset in -90..<30 {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: today) {
                let dayStart = calendar.startOfDay(for: date)
                let score = getDailyScore(for: dayStart)
                
                points.append(ChartDataPoint(
                    date: dayStart,
                    score: score
                ))
            }
        }
        
        dataPoints = points
    }
    
    private func findTodayIndex() -> Int? {
        let today = calendar.startOfDay(for: Date())
        return dataPoints.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) })
    }
    
    // MARK: - Score Calculations
    
    private func getDailyScore(for date: Date) -> Double? {
        let startOfDay = calendar.startOfDay(for: date)
        
        let dailyScore = scores.first { score in
            calendar.isDate(score.date, inSameDayAs: startOfDay)
        }
        
        return dailyScore?.averageScore
    }
    
    // MARK: - Helper Functions
    
    private func formatSelectedDate() -> String {
        guard let point = selectedDataPoint else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: point.date)
    }
    
    private func processPastDaysData(days: Int) {
        let today = Date()
        
        // Process past days
        for dayOffset in 0..<days {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            viewModel.calculateDayScore(for: date)
        }
        
        // Regenerate data points with the new data
        generateDataPoints()
        
        // Scroll to today
        if let todayIndex = findTodayIndex() {
            selectedIndex = todayIndex
        }
    }
}

// Helper view for displaying statistics
struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationView {
        ScrollablePrayerScoreView()
            .modelContainer(for: DailyPrayerScore.self, inMemory: true)
    }
}
*/

/*
import SwiftUI
import SwiftData
import Charts

struct ScrollablePrayerScoreView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var viewModel: PrayerViewModel
    @Query private var scores: [DailyPrayerScore]

    @State private var selectedDate = Date()
    
    /// The chart’s scrollPosition is basically the X-value at the *left edge*
    /// of the visible region. We’ll keep it in sync so that the selected date
    /// stays in the center. (Only available on iOS 17+)
    @State private var scrollPosition: Date = Date()

    private let calendar = Calendar.current
    private let startDate: Date
    private let endDate: Date

    init() {
        let today = Date()
        self.startDate = calendar.date(byAdding: .day, value: -90, to: today)!
        self.endDate   = calendar.date(byAdding: .day,  value:  30, to: today)!
    }

    var body: some View {
        VStack(spacing: 0) {
            modePicker

            headerView()
                .padding(.top, 20)

            chartView()
                .frame(height: 250)
                .padding(.top, 20)

            Text(formatSelectedDate())
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 10)

            statsView()
                .padding(.top, 10)

            Spacer()

//            processButton
        }
        .onAppear {
            // On appear, we set `selectedDate` to "today" and
            // scroll to keep it in the center:
            let today = calendar.startOfDay(for: Date())
            selectedDate = today
            scrollPosition = centerPosition(for: today)
        }
        .onChange(of: selectedDate) { newDate in
            // Whenever the user picks a new date (e.g. from tapping points),
            // also update `scrollPosition` to keep that date centered:
            scrollPosition = centerPosition(for: newDate)
        }
        .background(Color.black)
        .navigationTitle("Prayer Scores")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var modePicker: some View {
        Picker("View Mode", selection: .constant(0)) {
            Text("Daily").tag(0)
            Text("Weekly").tag(1)
            Text("Monthly").tag(2)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
        .padding(.top)
    }

    @ViewBuilder
    private func headerView() -> some View {
        if let score = getScoreForDate(selectedDate) {
            Text("\(Int(score * 100))%")
                .font(.system(size: 42, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        } else {
            Text("0%")
                .font(.system(size: 42, weight: .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }

    // Chart View
    @ViewBuilder
    private func chartView() -> some View {
        // Generate data points for the chart
        let dataPoints = generateDataPoints()
        
        Chart(dataPoints, id: \.date) { point in
            if let score = point.score {
                let isSelected = calendar.isDate(point.date, inSameDayAs: selectedDate)
                
                // Draw the connecting line
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", score * 100)
                )
                .foregroundStyle(.white)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                
                // Draw the data point
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Score", score * 100)
                )
                .foregroundStyle(isSelected ? .yellow : .white)
                .symbolSize(isSelected ? 14 : 8)
            }
        }
        // Y-axis styling
        .chartYAxis {
            AxisMarks(values: [0, 50, 75, 90, 100]) { value in
                if let doubleValue = value.as(Double.self) {
                    AxisGridLine(stroke: getGridLineStyle(for: doubleValue))
                    AxisValueLabel {
                        Text("\(Int(doubleValue))%")
                            .foregroundStyle(.gray)
                            .font(.caption2)
                    }
                }
            }
        }
        // X-axis styling
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                if let date = value.as(Date.self) {
                    AxisGridLine().foregroundStyle(.gray.opacity(0.3))
                    AxisValueLabel {
                        if isFirstOfMonth(date) {
                            Text(formatMonth(date))
                                .foregroundStyle(.gray)
                                .font(.caption2)
                        } else {
                            Text(formatDay(date))
                                .foregroundStyle(.gray)
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        // Enable horizontal scrolling and bind scroll position
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollPosition)
        .chartYScale(domain: 0...100)
        .chartXVisibleDomain(length: 3600 * 24 * 14) // 14 days visible
        // When scrollPosition changes, update the selected date
        .onChange(of: scrollPosition) { newValue in
//            if let newValue {
                selectedDate = calendar.startOfDay(for: newValue)
//            }
        }
        // Set initial position (centers on today's date)
        .onAppear {
            let today = Date()
            selectedDate = calendar.startOfDay(for: today)
            scrollPosition = today
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func statsView() -> some View {
        if let score = getScoreForDate(selectedDate) {
            HStack {
                StatView(
                    title: "Score",
                    value: String(format: "%.1f%%", score * 100)
                )
            }
            .padding(.horizontal)
        }
    }

//    private var processButton: some View {
//        Button("Process Last 100 Days") {
//            processPastDaysData(days: 100)
//        }
//        .buttonStyle(.borderedProminent)
//        .tint(Color.blue)
//        .padding()
//    }

    // MARK: - Helper Methods

    private func generateDataPoints() -> [DataPoint] {
        var points: [DataPoint] = []
        var currentDate = startDate

        while currentDate <= endDate {
            let score = getScoreForDate(currentDate)
            points.append(DataPoint(date: currentDate, score: score))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return points
    }

    private func getScoreForDate(_ date: Date) -> Double? {
        let startOfDay = calendar.startOfDay(for: date)
        return scores.first { score in
            calendar.isDate(score.date, inSameDayAs: startOfDay)
        }?.averageScore
    }

    /// Shifts the scrollPosition so that `date` is centered in the visible region.
    /// For a 14‐day wide domain, we shift by 7 days.
    private func centerPosition(for date: Date) -> Date {
        let halfRangeDays = 7
        // That means the left edge is `date - 7 days`
        return calendar.date(byAdding: .day, value: -halfRangeDays, to: date) ?? date
    }

    private func getGridLineStyle(for value: Double) -> StrokeStyle {
        let opacity: Double = 0.3
        let dash: [CGFloat] = [5, 5]

        if value == 90 || value == 75 || value == 50 {
            return StrokeStyle(lineWidth: 1, dash: dash, dashPhase: 0)
        } else {
            return StrokeStyle(lineWidth: 1, dash: [], dashPhase: 0)
        }
    }

    private func formatSelectedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: selectedDate)
    }

    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    private func isFirstOfMonth(_ date: Date) -> Bool {
        let components = calendar.dateComponents([.day], from: date)
        return components.day == 1
    }

    private func processPastDaysData(days: Int) {
        let today = Date()
        for dayOffset in 0..<days {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            viewModel.calculateDayScore(for: date)
        }
    }
}

// Same as before:
struct DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let score: Double?
}

struct StatView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationView {
        ScrollablePrayerScoreView()
            .modelContainer(for: DailyPrayerScore.self, inMemory: true)
    }
}
*/

import SwiftUI
import SwiftData

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
                    if let engScore = prayer.englishScore, let score = prayer.numberScore  {
                        Text("\(engScore)")
                            .font(.callout)
                            .foregroundColor(getColorForScore(score))
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
