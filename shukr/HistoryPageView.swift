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
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.presentationMode) var presentationMode

    @Environment(\.modelContext) private var context
    @Query private var sessionItems: [SessionDataModel]
    
    @Binding var showingHistoryPageBool: Bool
    
    // This is for testing in preview purposes. Uncomment other one out before using.
//    private var sessionItems: [SessionDataModel] = [
//        SessionDataModel( title: "same", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date(), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "same-60", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-60), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "same-60*60", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-60*60), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "same-1day", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-86400), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "same-2day", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-86400*2), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "same-2day and some", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-86405*2), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "1Alhamdulillah", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-3600), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "same-25days", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date().addingTimeInterval(-86400*24), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "2Alhamdulillah", sessionMode: 1,targetMin: 10, targetCount: 100, totalCount: 120, startTime: Date(), secondsPassed: 600, avgTimePerClick: 5, tasbeehRate: "12s", clickStats: []),
//        SessionDataModel( title: "3YaMuhammad YaRassollullah", sessionMode: 2, targetMin: 20, targetCount: 200, totalCount: 200, startTime: Date().addingTimeInterval(-3600), secondsPassed: 1200, avgTimePerClick: 6, tasbeehRate: "10s", clickStats: [])]
    
    @State private var showMantraSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var selectedSession: SessionDataModel? = nil // Track the selected session
    @State private var sessionToDelete: SessionDataModel? = nil // Track the session to delete
    
    @State private var dailyStatBool = true
    
    @State private var showAddTaskScreen = false
    
    @State private var selectedDate: Date = Date() // Starts with today
    @State private var selectedDateIndex: Int = 0
    
    @State var dateToCheckForToggle: Date = Date()
    
//    var totalDays: Int {
//        return 7 // Adjust to the number of days you want to allow scrolling through, e.g., last 7 days
//    }
    var totalDays: Int {
        guard let earliestSession = sessionItems.min(by: { $0.startTime < $1.startTime }),
              let latestSession = sessionItems.max(by: { $0.startTime < $1.startTime }) else {
            return 1 // Return 1 if there are no sessions or only one session
        }
        
        // Calculate the number of days between earliest and latest session
        let startOfEarliestSession = Calendar.current.startOfDay(for: earliestSession.startTime)
        let startOfLatestSession = Calendar.current.startOfDay(for: latestSession.startTime)
        
        let components = Calendar.current.dateComponents([.day], from: startOfEarliestSession, to: startOfLatestSession)
        
        return (components.day ?? 0) + 1 // +1 to include both start and end day
    }
    
    // Helper function to filter the sessions based on the selected date
    func filteredSessions(for date: Date) -> [SessionDataModel] {
        sessionItems.filter { session in
            Calendar.current.isDate(session.startTime, inSameDayAs: date)
        }
    }

    
    // Helper function to format the date label
    func dateLabel(for date: Date) -> String {
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
    
    
    var body: some View {
        
        ZStack{
            VStack{
                HStack{
                    
                    
                    
                    Button(action: {
                        // self.presentationMode.wrappedValue.dismiss()
                        triggerSomeVibration(type: .light)
                        withAnimation {
                            showingHistoryPageBool = false
                        }
                    }) {
                        HStack(spacing: 2) { // toggle daily stat section.
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .padding()
                        .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    DailyStatToggleView(dailyStatBool: $dailyStatBool, dateToCheck: $dateToCheckForToggle)
                        .padding(.horizontal, 10)
                }
                //                .padding(.horizontal, 20)
                
                HStack {
                    Text("Daily Tasks")
                        .font(.title)
                        .fontWeight(.thin)
                        .padding(.leading, 30)
                    Spacer()
                }
                DailyTasksView(showAddTaskScreen: $showAddTaskScreen)
                    .padding(.bottom, 15)
                
                
                
                
                
                
                
                HStack {
                    Text("Sessions")
                        .font(.title)
                        .fontWeight(.thin)
                        .padding(.leading, 30)
                    Spacer()
                }
                //                .background(.yellow)
                .padding(.bottom, -10)
                // Horizontal paging for different days
                VStack{
                    
                    TabView(selection: $selectedDateIndex) {
                    ForEach((0..<totalDays).reversed(), id: \ .self) { index in
                        let currentDate = Calendar.current.date(byAdding: .day, value: -index, to: Date())!
                        Text(dateLabel(for: currentDate))
                            .font(.subheadline)
                            .underline()
                            .foregroundStyle(.green)
                            .bold()
                            .frame(height: 50)
                            .padding(.horizontal, 10)
                            .tag(index)
                    }
                }
                .frame(height: 60)
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .onChange(of: selectedDateIndex, perform: { newValue in
                    dateToCheckForToggle = Calendar.current.date(byAdding: .day, value: -newValue, to: Date())!
                })

                // TabView with detailed sessions for the selected date
                TabView(selection: $selectedDateIndex) {
                    ForEach((0..<totalDays).reversed(), id: \ .self) { index in
                        let currentDate = Calendar.current.date(byAdding: .day, value: -index, to: Date())!
                        let sessionsForDay = filteredSessions(for: currentDate)

                        VStack {
                            Spacer()
                            if sessionsForDay.isEmpty {
                                Text("No sessions for this day")
                                    .font(.title3)
                                    .fontWeight(.thin)
                                    .padding()
                                Spacer()

                            } else {
                                ScrollView {
                                    LazyVStack {
                                        ForEach(sessionsForDay.sorted(by: { $0.startTime > $1.startTime }), id: \ .startTime) { session in
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
                                            .onTapGesture {
                                                selectedSession = session
                                                showMantraSheet = true
                                            }
                                            .onLongPressGesture(perform: {
                                                sessionToDelete = session
                                                showDeleteAlert = true
                                            })
                                        }
                                        if sessionsForDay.count >= 3 {
                                            Text("Nice! \(sessionsForDay.count) sessions \(index == 0 ? "today." : "")")
                                                .frame(height: 100)
                                                .fontWeight(.thin)
                                            
                                        }
                                        else if sessionsForDay.count >= 1 {
                                            Text(" Completed \(sessionsForDay.count) sessions \(index == 0 ? "today." : "")")
                                                .frame(height: 100)
                                                .fontWeight(.thin)
                                        }
                                        else if index == 0 {
                                            Text("Start another session to add more cards!")
                                                .frame(height: 70)
                                                .fontWeight(.thin)
                                        }
                                    }
                                }
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .alert(isPresented: $showDeleteAlert) {
                    Alert(
                        title: Text("Delete Session"),
                        message: Text("Are you sure you want to delete your \(sessionToDelete?.title ?? "") session?"),
                        primaryButton: .destructive(Text("Delete")) {
                            if let session = sessionToDelete {
                                 context.delete(session) // Uncomment when using a real context
                                sessionToDelete = nil
                            }
                        },
                        secondaryButton: .cancel {
                            sessionToDelete = nil
                        }
                    )
                }
                .sheet(isPresented: $showMantraSheet) {
                    MantraPickerView(isPresented: $showMantraSheet, selectedSession: $selectedSession)
                }
            }
            .onAppear {
                selectedDateIndex = 0
            }
                .onChange(of: selectedDateIndex){
                    dateToCheckForToggle = Calendar.current.date(byAdding: .day, value: -selectedDateIndex, to: Date())!
                }
                .frame(maxHeight: .infinity) // Give room for the sessions list to grow
                
            }
            .toolbar(content: {
                DailyStatToggleView(dailyStatBool: $dailyStatBool, dateToCheck: $dateToCheckForToggle)
                    .opacity(!showAddTaskScreen ? 1 : 0)
                    .animation(.easeInOut, value: showAddTaskScreen)
            })
            .toolbar(/*isPresented ? */.hidden /*: .visible*/, for: .navigationBar)
            .frame(maxWidth: .infinity)
            .background(Color("bgColor"))
            
            ZStack{
                AddDailyTaskView(isPresented: $showAddTaskScreen)
                
            }
            
        }
    }

    // Function to format date into a readable string for the session time
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
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
                    Text("Duration:")
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
    @Previewable @State var showingHistoryPageBool = true
    HistoryPageView(showingHistoryPageBool: $showingHistoryPageBool)
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
    // right now it pulls the stat by
    @Environment(\.modelContext) private var context
    @Query private var allSessionItems: [SessionDataModel]
    
    @Binding var dailyStatBool: Bool
    @Binding var dateToCheck: Date
    private var dailyStats: (Count: Int, Time: TimeInterval) { //not sure if this works with modelContainer / persistent data yet...
        var runningCount = 0
        var runningTime = 0.0
        let todaySessions = allSessionItems.filter { session in
//            Calendar.current.isDateInToday(session.startTime)
            Calendar.current.isDate(session.startTime, inSameDayAs: dateToCheck)

        }
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
                    .frame(width: 20, height: 20)
                Text("\(formatTime(dailyStats.Time))")
            } else {
                Image(systemName: "circle.grid.cross")
                    .frame(width: 20, height: 20)
                Text("\(dailyStats.Count)")
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
    @State private var searchQuery: String = ""
    private var predefinedMantras: [String] = ["Alhamdulillah", "Subhanallah", "Allahu Akbar", "Astaghfirullah"]
    
    // MantraItems from model context
    @Query private var mantraItems: [MantraModel]
    
    // Now use @Binding for selectedSession to watch changes
    @Binding var selectedSession: SessionDataModel?
    
    // Binding for controlling the visibility of the sheet
    @Binding var isPresented: Bool
    
    // Optional binding to pass the selected mantra, set to nil if not provided
    @Binding var selectedMantra: String?
    
    private var presentation: Set<PresentationDetent>

    // Allow selectedSession and selectedMantra to be optional in the initializer
    init(isPresented: Binding<Bool>, selectedSession: Binding<SessionDataModel?> = .constant(nil), selectedMantra: Binding<String?> = .constant(nil), presentation: Set<PresentationDetent>? = nil) {
        self._isPresented = isPresented
        self._selectedSession = selectedSession
        self._selectedMantra = selectedMantra
        self.presentation = presentation ?? [.medium]
    }
    
    var body: some View {
        VStack {
            // Search Bar
            TextField("Search or Add Mantra", text: $searchQuery)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            // Combine predefined and custom mantras, and filter by search query
            let filteredMantras = (predefinedMantras + mantraItems.map { $0.text })
                .filter { searchQuery.isEmpty || $0.lowercased().contains(searchQuery.lowercased()) }
                .sorted()
            
            if filteredMantras.isEmpty {
                // If no matches, show option to add new mantra
                Text("No results.")
                Text(" Add '\(searchQuery)' as a new mantra?")
                    .padding()
            } else {
                // Show filtered mantras
                List(filteredMantras, id: \.self) { existingMantra in
                    Button(action: {
                        if selectedSession != nil {
                            assignMantraToSession(existingMantra)
                        }
                        selectedMantra = existingMantra // Set the selected mantra if provided
                        isPresented = false // Close sheet after selecting
                    }) {
                        Text(existingMantra)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 10)
                .scrollContentBackground(.hidden)
            }
            
            Button("Add Mantra") {
                if !searchQuery.isEmpty {
                    saveToMantraList(searchQuery) // Save the mantra to model
                    if selectedSession != nil {
                        assignMantraToSession(searchQuery)
                    }
                    selectedMantra = searchQuery // Set the selected mantra if provided
                    isPresented = false // Close the sheet
                }
            }
            .disabled(searchQuery.isEmpty)
            .opacity(searchQuery.isEmpty ? 0 : 1)
            .padding()
            .onDisappear {
                searchQuery = ""
            }
        }
        .presentationDetents(presentation)
        .padding()
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



