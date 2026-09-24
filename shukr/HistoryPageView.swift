//
//  HistoryPageView.swift
//  shukr
//
//  Created on 9/25/24.
//

import SwiftUI
import SwiftData

import SwiftUI

/// Zikr history: every saved session, newest first, grouped by day, under an all-time total.
/// Reached from the hamburger menu. Rows show what the results screen showed for the session:
/// mantra, time, mode + target, count, duration and pace.
struct HistoryPageView: View {
    @Query(sort: \SessionDataModel.startTime, order: .reverse) private var sessions: [SessionDataModel]

    private var calendar: Calendar { Calendar.current }

    /// Sessions grouped by day, newest day first (the query is already newest-first).
    private var days: [(date: Date, sessions: [SessionDataModel])] {
        var order: [Date] = []
        var byDay: [Date: [SessionDataModel]] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.startTime)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(session)
        }
        return order.map { (date: $0, sessions: byDay[$0] ?? []) }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "circle.hexagonpath",
                    description: Text("Finished zikr sessions show up here.")
                )
            } else {
                Section("All time") {
                    LabeledContent("Sessions", value: sessions.count.formatted())
                    LabeledContent("Total count", value: sessions.reduce(0) { $0 + $1.totalCount }.formatted())
                    LabeledContent("Total time", value: zikrDurationString(sessions.reduce(0.0) { $0 + $1.secondsPassed }))
                }
                ForEach(days, id: \.date) { day in
                    Section {
                        ForEach(day.sessions) { session in
                            SessionRow(session: session)
                        }
                    } header: {
                        HStack {
                            Text(dayLabel(day.date))
                            Spacer()
                            Text("\(day.sessions.reduce(0) { $0 + $1.totalCount }) counted")
                        }
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .navigationTitle("Zikr History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayLabel(_ date: Date) -> String { zikrDayLabel(date) }
}

/// "Today", "Yesterday" or "Wed, Sep 24, 2026" — section headers in the history lists.
func zikrDayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
}

/// One session in a history list (Zikr History, and a mantra's sessions in its editor).
struct SessionRow: View {
    let session: SessionDataModel

    private var modeIcon: String {
        switch session.sessionMode {
        case 1: return "timer"
        case 2: return "number"
        default: return "infinity"
        }
    }
    private var target: String {
        switch session.sessionMode {
        case 1: return "\(session.targetMin)m"
        case 2: return "\(session.targetCount)"
        default: return "freestyle"
        }
    }
    /// Seconds per count, derived the same way the mantra's pace is (duration / count) so the
    /// two pages agree; the stored `avgTimePerClick` was sampled mid-session and runs a little low.
    private var pace: TimeInterval? {
        guard session.totalCount > 0, session.secondsPassed > 0 else { return nil }
        return session.secondsPassed / Double(session.totalCount)
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.mantra?.name ?? session.title)
                    .font(.body.weight(.medium))
                HStack(spacing: 4) {
                    Text(session.startTime, style: .time)
                    Text("·")
                    Image(systemName: modeIcon)
                    Text(target)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(session.totalCount.formatted())
                    .font(.title3.weight(.semibold))
                Text(pace.map { "\(zikrDurationString(session.secondsPassed)) · \(String(format: "%.1fs", $0)) each" }
                     ?? zikrDurationString(session.secondsPassed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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

/// Pick (or add) a mantra. Hands back the `MantraModel` through `selectedMantraObject` and its
/// name through `selectedMantra` (the name is what most callers display; the object is what
/// tasks and sessions link to). The object is set first, so an `onChange` on the name sees it.
struct MantraPickerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MantraModel.name) private var mantraItems: [MantraModel]

    // Binding for controlling the visibility of the sheet
    @Binding var isPresented: Bool
    @Binding var selectedMantra: String?
    @Binding var selectedMantraObject: MantraModel?
    @Binding var selectedSession: SessionDataModel?

    @State private var searchQuery: String = ""
    @State private var showAlertToAdd: Bool = false

    private var presentation: Set<PresentationDetent>
    private var filteredMantras: [MantraModel] {
        mantraItems.filter { searchQuery.isEmpty || $0.name.lowercased().contains(searchQuery.lowercased()) }
    }
    private var  uniqueItem: Bool {
        !mantraItems.contains { $0.name.lowercased() == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    // Allow selectedSession and selectedMantra to be optional in the initializer
    init(isPresented: Binding<Bool>, selectedSession: Binding<SessionDataModel?> = .constant(nil), selectedMantra: Binding<String?> = .constant(nil), selectedMantraObject: Binding<MantraModel?> = .constant(nil), presentation: Set<PresentationDetent>? = nil) {
        self._isPresented = isPresented
        self._selectedSession = selectedSession
        self._selectedMantra = selectedMantra
        self._selectedMantraObject = selectedMantraObject
        self.presentation = presentation ?? [.medium]
    }

    /// Every way out of the picker ends here.
    private func select(_ mantra: MantraModel) {
        if selectedSession != nil { assignMantraToSession(mantra) }
        selectedMantraObject = mantra
        selectedMantra = mantra.name
        isPresented = false
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
                        select(saveToMantraList(searchQuery))
                    }
                }
                .padding()
                Spacer()
            } else {

                // List instead of Wheel Picker
                List(filteredMantras) { mantra in
                    Button(mantra.name) { select(mantra) }
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
                            select(saveToMantraList(searchQuery))
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
    
    /// The mantra with this name, creating it if there isn't one.
    private func saveToMantraList(_ name: String) -> MantraModel {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = mantraItems.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            return existing
        }
        let newMantraItem = MantraModel(name: trimmed)
        context.insert(newMantraItem)
        print("Saved new mantra: \(trimmed)")
        return newMantraItem
    }

    // Conditionally assign the mantra to a session if selectedSession is not nil
    private func assignMantraToSession(_ mantra: MantraModel) {
        if let session = selectedSession {
            session.title = mantra.name
            session.mantra = mantra
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



