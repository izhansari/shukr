//
//  HistoryPageView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData


struct HistoryPageView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessionItems: [SessionDataModel]
    @Query private var mantraItems: [MantraModel]
    
//    private var sessionItems: [SessionDataModel] = [
//        SessionDataModel(
//            title: "Morning Tasbeeh",
//            sessionMode: 1,
//            targetMin: 10,
//            targetCount: 100,
//            totalCount: 120,
//            startTime: Date(),
//            secondsPassed: 600,
//            sessionDuration: "10m",
//            avgTimePerClick: 5,
//            tasbeehRate: "12s",
//            clickStats: []
//        ),
//        SessionDataModel(
//            title: "Evening Tasbeeh",
//            sessionMode: 2,
//            targetMin: 20,
//            targetCount: 200,
//            totalCount: 200,
//            startTime: Date().addingTimeInterval(-3600),
//            secondsPassed: 1200,
//            sessionDuration: "20m",
//            avgTimePerClick: 6,
//            tasbeehRate: "10s",
//            clickStats: []
//        )
//    ]
    
    @State private var showSheet: Bool = false
    @State private var searchQuery: String = "" // This is used for the search bar
    @State private var selectedSession: SessionDataModel? = nil // Track the selected session
    @State private var showDeleteAlert: Bool = false // Track if delete confirmation is showing
    @State private var sessionToDelete: SessionDataModel? = nil // Track the session to delete
    @State private var sessionToDeleteTitle: String = ""
    private var sessionToDeleteTitle2: String{
        return sessionToDelete?.title ?? ""
    }
    
    @State private var dailyStatBool = true

//    private var dayStat: (Count: Int, Time: TimeInterval){
//        var runningCount = 0
//        var runningTime = 0.0
//        var index = 0
//        while index != sessionItems.count{
//            let session = sessionItems[index]
//            runningCount += session.totalCount
//            runningTime += session.secondsPassed
////            print("at \(index) the count is \(session.totalCount) and time is \(session.secondsPassed)")
//            index += 1
//        }
//        return (runningCount, runningTime)
//    }
    
    private var dailyStats: (Count: Int, Time: TimeInterval) { //not sure if this works with modelContainer / persistent data yet...
        var runningCount = 0
        var runningTime = 0.0
        for session in sessionItems {
            runningCount += session.totalCount
            runningTime += session.secondsPassed
        }
        return (runningCount, runningTime)
    }

    
    let predefinedMantras = ["Alhamdulillah", "Subhanallah", "Allahu Akbar", "Astaghfirullah"]
    
    var body: some View {
        VStack{
            VStack {
                HStack {
                    Spacer()
                    
                    
//                    HStack(alignment: .center) { // toggle daily stat section.
//                        if dailyStatBool {
//                            Image(systemName: "clock")
//                                .frame(width: 20, height: 20)
//                            Text("\(formatTime(dailyStats.Time))")
//                        } else {
//                            Image(systemName: "circle.grid.cross")
//                                .frame(width: 20, height: 20)
//                            Text("\(dailyStats.Count)")
//                        }
//                    }
//                    .padding(10)
//                    .frame(width: 120, height: 40) // Set fixed width and height to prevent jumping
//                    .background(Color.gray.opacity(0.1))
//                    .cornerRadius(10)
//                    .onTapGesture {
//                        dailyStatBool.toggle()
//                    }
                    
                    
                }
                .edgesIgnoringSafeArea(.top)
                .padding(.top, 20)
                .padding(.horizontal, 10)
                .padding(.bottom, 5)
            }
            
            HStack {
                Text("Daily Tasks")
                    .font(.title)
                    .fontWeight(.thin)
                    .padding(.leading, 30)
                Spacer()
            }
            DailyTasksView()
                .padding(.bottom, 20)
            
            HStack {
                Text("Sessions")
                    .font(.title)
                    .fontWeight(.thin)
                    .padding(.leading, 30)
                Spacer()
            }
            VStack {
                if sessionItems.isEmpty {
                    Spacer()
                    Text("No sessions yet buddy...")
                        .font(.title)
                        .fontWeight(.thin)
                        .padding()
                    Spacer()
                }
                else {
                    ScrollView {
                        VStack {
                            ForEach(sessionItems.sorted(by: { $0.startTime > $1.startTime }), id: \.startTime) { session in
                                SessionCardView(
                                    title: session.title,
                                    sessionMode: session.sessionMode,
                                    totalCount: session.totalCount,
                                    sessionDuration: session.sessionDuration,
                                    sessionTime: formatDate(session.startTime),
                                    tasbeehRate: session.tasbeehRate,
                                    targetMin: session.targetMin,
                                    targetCount: "\(session.targetCount)"
                                )
                                .onTapGesture {
                                    selectedSession = session // Assign tapped session
                                    showSheet = true // Show the sheet
                                }
                                .onLongPressGesture(perform: {
                                    sessionToDelete = session
                                    sessionToDeleteTitle = session.title
                                    showDeleteAlert = true // Show confirmation alert
                                })
                            }
                        }
                    }
                    .alert(isPresented: $showDeleteAlert) {
                        Alert(
                            title: Text("Delete Session"),
                            message: Text("Are you sure you want to delete your \(sessionToDeleteTitle2) session?"),
                            primaryButton: .destructive(Text("Delete")) {
                                if let session = sessionToDelete {
                                    context.delete(session) // Delete from SwiftData
                                    sessionToDelete = nil // Reset the sessionToDelete
                                    
                                }
                            },
                            secondaryButton: .cancel {
                                sessionToDelete = nil // Reset the sessionToDelete
                            }
                        )
                    }
                    //            .background(Color("bgColor"))
                    .sheet(isPresented: $showSheet) {
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
                                List(filteredMantras, id: \.self) { mantra in
                                    Button(action: {
                                        if let session = selectedSession {
                                            session.title = mantra
                                        }
                                        showSheet = false // Close sheet after selecting
                                    }) {
                                        Text(mantra)
                                    }
                                }
                            }
                            
                            Button("Add Mantra") {
                                if !searchQuery.isEmpty {
                                    saveMantra(searchQuery) // Save new mantra from search bar input
                                    showSheet = false // Close the sheet
                                }
                            }
                            .disabled(searchQuery.isEmpty)
                            .padding()
                            .onDisappear{
                                searchQuery = ""
                            }
                        }
                        //                .background(Color.red)
                        .presentationDetents([.medium])
                        .padding()
                    }
                }
            }
        }
        .toolbar(content: {
            
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
            
            
        })
        .frame(maxWidth: .infinity)
        .background(Color("bgColor"))

//        if sessionItems.isEmpty {
//            VStack {
//                Spacer()
//                Text("No sessions yet buddy...")
//                    .font(.title)
//                    .fontWeight(.thin)
//                    .padding()
//                Spacer()
//            }
//            .frame(maxWidth: .infinity)
//            .background(Color("bgColor"))
//        }
//        else {
//            VStack{
//                ScrollView {
//                    VStack {
//                        ForEach(sessionItems.sorted(by: { $0.startTime > $1.startTime }), id: \.startTime) { session in
//                            SessionCardView(
//                                title: session.title,
//                                sessionMode: session.sessionMode,
//                                totalCount: session.totalCount,
//                                sessionDuration: session.sessionDuration,
//                                sessionTime: formatDate(session.startTime),
//                                tasbeehRate: session.tasbeehRate,
//                                targetMin: session.targetMin,
//                                targetCount: "\(session.targetCount)"
//                            )
//                            .onTapGesture {
//                                selectedSession = session // Assign tapped session
//                                showSheet = true // Show the sheet
//                            }
//                            .onLongPressGesture(perform: {
//                                sessionToDelete = session
//                                sessionToDeleteTitle = session.title
//                                showDeleteAlert = true // Show confirmation alert
//                            })
//                        }
//                    }
//                }
//                .alert(isPresented: $showDeleteAlert) {
//                    Alert(
//                        title: Text("Delete Session"),
//                        message: Text("Are you sure you want to delete your \(sessionToDeleteTitle2) session?"),
//                        primaryButton: .destructive(Text("Delete")) {
//                            if let session = sessionToDelete {
//                                context.delete(session) // Delete from SwiftData
//                                sessionToDelete = nil // Reset the sessionToDelete
//                                
//                            }
//                        },
//                        secondaryButton: .cancel {
//                            sessionToDelete = nil // Reset the sessionToDelete
//                        }
//                    )
//                }
//                //            .background(Color("bgColor"))
//                .sheet(isPresented: $showSheet) {
//                    VStack {
//                        // Search Bar
//                        TextField("Search or Add Mantra", text: $searchQuery)
//                            .textFieldStyle(RoundedBorderTextFieldStyle())
//                            .padding()
//                        
//                        // Combine predefined and custom mantras, and filter by search query
//                        let filteredMantras = (predefinedMantras + mantraItems.map { $0.text })
//                            .filter { searchQuery.isEmpty || $0.lowercased().contains(searchQuery.lowercased()) }
//                            .sorted()
//                        
//                        if filteredMantras.isEmpty {
//                            // If no matches, show option to add new mantra
//                            Text("No results.")
//                            Text(" Add '\(searchQuery)' as a new mantra?")
//                                .padding()
//                        } else {
//                            // Show filtered mantras
//                            List(filteredMantras, id: \.self) { mantra in
//                                Button(action: {
//                                    if let session = selectedSession {
//                                        session.title = mantra
//                                    }
//                                    showSheet = false // Close sheet after selecting
//                                }) {
//                                    Text(mantra)
//                                }
//                            }
//                        }
//                        
//                        Button("Add Mantra") {
//                            if !searchQuery.isEmpty {
//                                saveMantra(searchQuery) // Save new mantra from search bar input
//                                showSheet = false // Close the sheet
//                            }
//                        }
//                        .disabled(searchQuery.isEmpty)
//                        .padding()
//                        .onDisappear{
//                            searchQuery = ""
//                        }
//                    }
//                    //                .background(Color.red)
//                    .presentationDetents([.medium])
//                    .padding()
//                }
//            }
////            .frame(maxWidth: .infinity)
//            .background(Color("bgColor"))
//        }
    }

    // Function to save a new or selected mantra
    private func saveMantra(_ mantra: String) {
        if let session = selectedSession {
            session.title = mantra
            
            let isInPredefined = predefinedMantras.contains(mantra)
            let isInCustomMantras = mantraItems.contains(where: { $0.text == mantra })

            // Check if the mantra already exists in SwiftData
            if !isInPredefined && !isInCustomMantras{
                let newMantraItem = MantraModel(text: mantra)
                context.insert(newMantraItem) // Insert new mantra into SwiftData
                print("Saved new mantra: \(mantra)")
            }
            else {
                print("Mantra already exists")
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

    // Function to format date into a readable string for the session time
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        var components: [String] = []

        if hours > 0 {
            components.append("\(hours)h")
        }
        if minutes > 0 {
            components.append("\(minutes)m")
        }
        if seconds > 0 {
            components.append("\(seconds)s")
        }

        return components.isEmpty ? "0" : components.joined(separator: " ")
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
                
                Image(systemName: sessionModeIcon)
                    .font(.title3)
                    .foregroundColor(.gray)
                Text(sessionMode != 0 ? textForTarget : "")
                    .font(.title3)
                    .foregroundColor(.gray)
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

struct ContentView: View {
    var body: some View {
        HistoryPageView()
    }
}

#Preview {
    return ContentView()
}




