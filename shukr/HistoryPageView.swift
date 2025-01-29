//
//  HistoryPageView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData

import SwiftUI

struct HistoryPageView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var sessionItems: [SessionDataModel]
    @EnvironmentObject var sharedState: SharedStateClass
    
    @State private var selectedDateIndex: Int = 0
    @State private var dailyStatBool = true
    
    private var calendar: Calendar { Calendar.current }
    
    private var availableDates: [Date] {
        let dates = Set(sessionItems.map { calendar.startOfDay(for: $0.startTime) })
        return Array(dates).sorted(by: <) // Ascending order (older dates first)
    }
    
    private func sessions(for date: Date) -> [SessionDataModel] {
        sessionItems
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .sorted(by: { $0.startTime > $1.startTime })
    }
    
    private func exitPage() {
        triggerSomeVibration(type: .light)
        dismiss()
    }
    
    var body: some View {
        ZStack{
            VStack(alignment: .leading) {
//                HStack {
//                    DailyStatToggleView(dailyStatBool: $dailyStatBool)
//
//                    Spacer()
//
//                    Button(action: {
//                        exitPage()
//                    }) {
//                        RoundedRectangle(cornerRadius: 15)
//                            .fill(Color.clear.opacity(0.1))
//                            .frame(width: 70, height: 70)
//                            .overlay(
//                                VStack(spacing: 10) {
//                                    Image(systemName: "xmark")
//                                        .frame(width: 30, height: 30)
//                                        .foregroundColor(.gray)
//                                }
//                            )
//                    }
//                }
//                .padding([.top, .leading])
                
                
                

//                Text("Tasks")
//                    .font(.title)
//                    .fontWeight(.thin)
//                    .padding(.leading, 30)
//                
//                DailyTasksView()
//                    .padding(.bottom, 15)
                
                
                Text("Sessions")
                    .font(.title)
                    .fontWeight(.thin)
                    .padding(.leading, 30)
                
                Text(myDateLabel)
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(.green)
                    .bold()
                    .frame(height: 50)
                    .frame(maxWidth: .infinity)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(availableDates.enumerated()), id: \.element) { index, date in
                            DayView(date: date, sessions: sessions(for: date))
                                .frame(width: UIScreen.main.bounds.width)
                                .containerRelativeFrame(.horizontal, alignment: .center)
                        }
                    }
                }
                .scrollTargetLayout()
                .scrollTargetBehavior(.paging)
                .defaultScrollAnchor(.trailing) // this is how we get it to show middle page on load.
                .scrollPosition(id: .init(get: {
                    selectedDateIndex
                }, set: { newPosition in
                    if let newPos = newPosition {
                        selectedDateIndex = newPos
                    }
                }))
            }
            .onAppear {
                // Set initial index to the last item (most recent date)
                selectedDateIndex = 0
            }
        }
//        .navigationBarBackButtonHidden(true)
//        .navigationTitle("History")
        .toolbar {
            
            ToolbarItem(placement: .principal) {
                DailyStatToggleView(dailyStatBool: $dailyStatBool)
            }
        }

    }
    
    private var myDateLabel: String {
        let date = availableDates[safe: selectedDateIndex] ?? Date()
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "E, MMM d"
            return formatter.string(from: date)
        }
    }
    
    private func dateLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "E, MMM d"
            return formatter.string(from: date)
        }
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct DayView: View {
    let date: Date
    let sessions: [SessionDataModel]
    
    private var dateString: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "E, MMM d"
            return formatter.string(from: date)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(dateString)
                .font(.headline)
                .padding(.horizontal)
            
            if sessions.isEmpty {
                Text("No sessions for this day")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(sessions) { session in
                            //                            SessionRowView(session: session)
                            //                                .padding(.horizontal)
                            SessionCardView(
                                title: session.title,
                                sessionMode: session.sessionMode,
                                totalCount: session.totalCount,
                                sessionDuration: session.timeDurationString,
                                sessionTime: formatDate(session.startTime),
                                tasbeehRate: session.tasbeehRate,
                                targetMin: session.targetMin,
                                targetCount: "\(session.targetCount)"
                            )
                        }
                    }
                }
            }
        }
    }
}

struct SessionCardView: View {
    let title: String
    let sessionMode: Int // 0 for freestyle, 1 for timed, 2 for count target mode
    let totalCount: Int
    let sessionDuration: String
    let sessionTime: String
    let tasbeehRate: String
    let targetMin: Int
    let targetCount: String
    
    @Environment(\.colorScheme) var colorScheme


    var sessionModeIcon: String {
        switch sessionMode {
        case 0: return "infinity"  // Freestyle
        case 1: return "timer"     // Timed mode
        case 2: return "number"    // Count target mode
        default: return "questionmark" // Fallback
        }
    }
    
    var textForTarget: String{
        switch sessionMode {
        case 0: return ""  // Freestyle
        case 1: return "\(targetMin)m"     // Timed mode
        case 2: return targetCount    // Count target mode
        default: return "?!*" // Fallback
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            
            // Top Section: Title and Mode Icon
            HStack {
                VStack(alignment: .leading){
                    Text(title)
                        .font(.title2)
                        .bold()
                    Text(sessionTime)
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                HStack(spacing: 2){
                    Image(systemName: sessionModeIcon)
                        .font(.title3)
                        .foregroundColor(.gray)
                    Text(sessionMode != 0 ? textForTarget : "")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
            

            // Middle Section: Count, Duration, (Optional Section)
            HStack {
                Spacer()
                
                // First Section (Count)
                VStack{
                    Text("Count:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(totalCount)")
                        .font(.subheadline)
                }
                
                Spacer()

                // Second Section (Session Duration)
                VStack{
                    Text("Time:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(sessionDuration)")
                        .font(.subheadline)
                }

                Spacer()
                
                // Third Section (Session Duration)
                VStack{
                    Text("Rate:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(tasbeehRate)")
                        .font(.subheadline)
                }
                
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal)
        }
        .padding()
        .background(BlurView(style: .systemUltraThinMaterial)) // Blur effect for the exit button
        .cornerRadius(15)
        .padding(.horizontal)
    }
}

#Preview {
    HistoryPageView()
}

//// Helper view for footer text
struct FooterText: View {
    let sessionCount: Int
    let index: Int
    
    var body: some View {
        Group {
            if sessionCount >= 3 {
                Text("Nice! \(sessionCount) sessions \(index == 0 ? "today." : "")")
                    .frame(height: 100)
                    .fontWeight(.thin)
            } else if sessionCount >= 1 {
                Text("Completed \(sessionCount) sessions \(index == 0 ? "today." : "")")
                    .frame(height: 100)
                    .fontWeight(.thin)
            } else if index == 0 {
                Text("Start another session to add more cards!")
                    .frame(height: 70)
                    .fontWeight(.thin)
            }
        }
    }
}



#Preview {
//    @Previewable @State var showingHistoryPageBool = true
    HistoryPageView(/*showingHistoryPageBool: $showingHistoryPageBool*/)
}


func formatTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
//    let seconds = Int(time) % 60

    var components: [String] = []

    if hours > 0 {
        components.append("\(hours)h")
    }
    if minutes > 0 {
        components.append("\(minutes)m")
    }

    if( (Int(time) > 0) && (Int(time) < 60) ){
        return "<1m"
    }
    
    return components.isEmpty ? "0m" : components.joined(separator: " ")
}


struct DailyStatToggleView: View {

    @Environment(\.modelContext) private var context
  
    static var descriptor: FetchDescriptor<SessionDataModel> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        
        let predicate = #Predicate<SessionDataModel> { session in
            session.startTime >= today && session.startTime < tomorrow
        }
        
        let descriptor = FetchDescriptor<SessionDataModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return descriptor
    }

    @Query(descriptor) var todaySessions: [SessionDataModel]
    
    @Binding var dailyStatBool: Bool
//    @Binding var dateToCheck: Date
    private var dailyStats: (Count: Int, Time: TimeInterval) { //not sure if this works with modelContainer / persistent data yet...
        var runningCount = 0
        var runningTime = 0.0

        for session in todaySessions {
            runningCount += session.totalCount
            runningTime += session.secondsPassed
        }
        return (runningCount, runningTime)
    }
    
    var body: some View {
        HStack(alignment: .center) { // toggle daily stat section.
            if dailyStatBool {
                Image(systemName: "clock")
//                    .frame(width: 20, height: 20)
                    .font(.system(size: 12))
//                    .padding(.leading)
//                Spacer()
                Text("\(timerStyle(dailyStats.Time/60))")
//                Spacer()
            } else {
                Image(systemName: "circle.hexagonpath")
//                    .frame(width: 20, height: 20)
                    .font(.system(size: 12))
//                    .padding(.leading)
//                Spacer()
                Text("\(dailyStats.Count)")
//                Spacer()
            }
        }
        .padding(10)
        .frame(width: 120, height: 40) // Set fixed width and height to prevent jumping
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
        .onTapGesture {
            dailyStatBool.toggle()
        }
    }
}

struct MantraPickerView: View {
    @Environment(\.modelContext) private var context
    @Query private var mantraItems: [MantraModel]
    
    // Binding for controlling the visibility of the sheet
    @Binding var isPresented: Bool
    @Binding var selectedMantra: String?
    @Binding var selectedSession: SessionDataModel?

    @State private var searchQuery: String = ""
    @State private var tempSelection: String?
    @State private var showAlertToAdd: Bool = false
        
    private var predefinedMantras: [String] = ["Alhamdulillah", "Subhanallah", "Allahu Akbar", "Astaghfirullah"]
    private var presentation: Set<PresentationDetent>
    private var filteredMantras: [String]{
        (predefinedMantras + mantraItems.map { $0.text })
            .filter { searchQuery.isEmpty || $0.lowercased().contains(searchQuery.lowercased()) }
            .sorted()
    }
    private var  uniqueItem: Bool {
        (predefinedMantras + mantraItems.map { $0.text })
            .filter { $0.lowercased() == searchQuery.lowercased() }
            .isEmpty
    }
    
    // Allow selectedSession and selectedMantra to be optional in the initializer
    init(isPresented: Binding<Bool>, selectedSession: Binding<SessionDataModel?> = .constant(nil), selectedMantra: Binding<String?> = .constant(nil), presentation: Set<PresentationDetent>? = nil) {
        self._isPresented = isPresented
        self._selectedSession = selectedSession
        self._selectedMantra = selectedMantra
        self.presentation = presentation ?? [.medium]
    }
  
    
//    var body: some View {
//        VStack {
//            // Search Bar
//            TextField("Search or Add Zikr", text: $searchQuery)
//                .textFieldStyle(RoundedBorderTextFieldStyle())
//                .padding()
//            
//            // Combine predefined and custom mantras, and filter by search query
//            let filteredMantras = (predefinedMantras + mantraItems.map { $0.text })
//                .filter { searchQuery.isEmpty || $0.lowercased().contains(searchQuery.lowercased()) }
//                .sorted()
//            
//            if filteredMantras.isEmpty {
//                // If no matches, show option to add new mantra
//                Text("No results.")
//                Text(" Add '\(searchQuery)' as a new zikr?")
//                    .padding()
//            } else {
//                
//                Spacer()
//                
//                Picker("Select Mantra", selection: $tempSelection) {
//                    ForEach(filteredMantras, id: \.self) { existingMantra in
//                        Text(existingMantra).tag(existingMantra)
//                    }
//                }
//                .pickerStyle(.wheel)
//                .frame(height: 150) // Adjust the height as needed
//                
//                Spacer()
//                
//            }
//            
//            Button("Add Zikr") {
//                if !searchQuery.isEmpty {
//                    saveToMantraList(searchQuery) // Save the mantra to model
//                    if selectedSession != nil {
//                        assignMantraToSession(searchQuery)
//                    }
//                    selectedMantra = searchQuery // Set the selected mantra if provided
//                    isPresented = false // Close the sheet
//                }
//            }
//            .disabled(searchQuery.isEmpty || !filteredMantras.isEmpty)
//            .opacity(searchQuery.isEmpty || !filteredMantras.isEmpty ? 0 : 1)
//            .padding()
//            .onDisappear {
//                searchQuery = ""
//            }
//            
//            if !filteredMantras.isEmpty {
//                Button("Confirm") {
//                    if let pickedMantra = tempSelection, selectedSession != nil {
//                        assignMantraToSession(pickedMantra)
//                    }
//                    selectedMantra = tempSelection
//                }
//                .foregroundStyle(.green.opacity(0.7))
//                .buttonStyle(.bordered)
//                .padding(.bottom)
//            }
//            Spacer()
//        }
//        .padding(.top)
//        .onChange(of: selectedMantra) {_, newValue in
//            // This will be called whenever the selection changes
//            print("Selected mantra: \(newValue ?? "nil")")
//        }
//        .onDisappear{
////            if let pickedMantra = selectedMantra, selectedSession != nil {
////                assignMantraToSession(pickedMantra)
////            }
//        }
//        .presentationDetents(presentation)
//        .padding()
//    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // Search Bar and Add Button
            HStack {
                TextField("Search or Add Zikr", text: $searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocorrectionDisabled(true)
                
                    Button(action: {
                        showAlertToAdd = true
                    }) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.green.opacity(0.7))
                    }
                    .opacity(searchQuery.isEmpty || !uniqueItem ? 0.3 : 1)
                    .disabled(searchQuery.isEmpty || !uniqueItem)
            }
            .padding()
            
            
            if filteredMantras.isEmpty {
                Spacer()
                // If no matches, show option to add new mantra
                VStack {
                    Text("No results.")
                    Text("Add '\(searchQuery)' as a new zikr?")
                    Button("Add") {
                        // Add new Zikr
                        saveToMantraList(searchQuery)
                        if selectedSession != nil {
                            assignMantraToSession(searchQuery)
                        }
                        selectedMantra = searchQuery
                        isPresented = false // Close the sheet
                    }
                }
                .padding()
                Spacer()
            } else {
                
                // List instead of Wheel Picker
                List(filteredMantras, id: \.self, selection: $tempSelection) { existingMantra in
                    Button(existingMantra){
                            // Confirm existing Zikr
                            if selectedSession != nil {
                                assignMantraToSession(existingMantra)
                            }
                            selectedMantra = existingMantra
                        isPresented = false // Close the sheet
                    }
                    .tint(Color.primary)
                }
                .listStyle(DefaultListStyle())
            }
        }
        .alert(isPresented: $showAlertToAdd) {
                    Alert(
                        title: Text("Add this to list?"),
                        message: Text("\(searchQuery)"),
                        primaryButton: .default(Text("Add")) {
                            // Add new Zikr
                            saveToMantraList(searchQuery)
                            if selectedSession != nil {
                                assignMantraToSession(searchQuery)
                            }
                            selectedMantra = searchQuery
                            isPresented = false // Close the sheet
                        },
                        secondaryButton: .cancel()
                    )
                }
        .onChange(of: selectedMantra) { _, newValue in
            print("Selected mantra: \(newValue ?? "nil")")
        }
        .onDisappear {
            searchQuery = ""
        }
//        .presentationDetents(presentation)
    }
    
    // Function to save a new or selected mantra
    private func saveToMantraList(_ mantra: String) {
        let isInPredefined = predefinedMantras.contains(mantra)
        let isInCustomMantras = mantraItems.contains(where: { $0.text == mantra })
        
        // Check if the mantra already exists
        if !isInPredefined && !isInCustomMantras {
            let newMantraItem = MantraModel(text: mantra)
            context.insert(newMantraItem) // Insert new mantra into SwiftData
            print("Saved new mantra: \(mantra)")
        } else {
            print("Mantra already exists")
        }
    }
    
    // Conditionally assign the mantra to a session if selectedSession is not nil
    private func assignMantraToSession(_ mantra: String) {
        if let session = selectedSession {
            session.title = mantra
            do {
                try context.save()  // Save the context to persist the changes
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    // Function to delete custom mantra
    private func deleteMantra(at offsets: IndexSet) {
        for index in offsets {
            let mantra = mantraItems[index]
            context.delete(mantra) // Delete from SwiftData
        }
    }
}



