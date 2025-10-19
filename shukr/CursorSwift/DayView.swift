//
//  DayView.swift
//  shukr
//
//  Created by Izhan S Ansari on 3/6/25.
//

import SwiftUI

struct ScrollDayView: View {
    let date: Date
    
    // DateFormatter for M/d format
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
    
    var body: some View {
        VStack {
//            HStack {
//                Text(date, format: .dateTime.month())
//                Text(date, format: .dateTime.day())
//            }
//            .font(.largeTitle)
//            Text(date, format: .dateTime.weekday())
//                .font(.subheadline)
            Text("\(dateFormatter.string(from: date))")
        }
//        .frame(width: UIScreen.main.bounds.width)
    }
}

struct InfiniteDaysScrollView: View {
    @State private var dates: [Date] = []
    @State private var currentIndex: Int?
    @State private var doneScrollingToToday = false
    @Binding var selectedDate: Date // Track the selected date
    
    var body: some View {
        VStack {
//            // Display the selected date
//            Text("Selected Date: \(selectedDate.formatted(date: .long, time: .omitted))")
//                .font(.title2)
//                .padding()
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(dates.enumerated()), id: \.element) { index, date in
                        ScrollDayView(date: date)
                            .id(index)
                            .containerRelativeFrame(.horizontal, alignment: .center)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentIndex)
            .onAppear {
                initializeDates()
                // Scroll to the current date after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    currentIndex = 20 // Start with today
                    withAnimation {
                        doneScrollingToToday = true
                    }
                }
            }
            .onChange(of: currentIndex) { oldValue, newValue in
                guard let newIndex = newValue else { return }
                
                // Update selected date when the index changes
                if dates.indices.contains(newIndex) {
                    selectedDate = dates[newIndex]
                    print("Selected date updated to: \(selectedDate.formatted())")
                }
                
                // Prepend when within 10 days of the beginning
                if newIndex < 10 {
                    prependDates()
                }
                // Append when within 10 days of the end
                else if newIndex > dates.count - 10 {
                    appendDates()
                }
            }
            .opacity(doneScrollingToToday ? 1 : 0)
        }
    }
    
    private func initializeDates() {
        let today = Date()
        // Create dates from 20 days before today to 20 days after today
        dates = (-20...20).map { Calendar.current.date(byAdding: .day, value: $0, to: today)! }
        selectedDate = today // Set initial selected date to today
    }
    
    private func prependDates() {
        let oldFirstDate = dates.first!
        // Add 10 more days at the beginning
        let newDates = (1...10).map { Calendar.current.date(byAdding: .day, value: -$0, to: oldFirstDate)! }.reversed()
        dates.insert(contentsOf: newDates, at: 0)
        
        // Adjust currentIndex to maintain the same visual position
        currentIndex = (currentIndex ?? 0) + 10
    }
    
    private func appendDates() {
        let oldLastDate = dates.last!
        // Add 10 more days at the end
        let newDates = (1...10).map { Calendar.current.date(byAdding: .day, value: $0, to: oldLastDate)! }
        dates.append(contentsOf: newDates)
    }
}

//struct InfiniteDaysScrollView_Previews: PreviewProvider {
//    static var previews: some View {
//        InfiniteDaysScrollView()
//    }
//}
