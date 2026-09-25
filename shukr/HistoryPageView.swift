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
    @Environment(\.modelContext) private var context
    /// Swipe → delete asks first.
    @State private var pendingDelete: SessionDataModel?
    /// Swipe the other way → that session's mantra (its stats + editor).
    @State private var mantraToOpen: MantraModel?

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
                                // Swipe left: delete (confirmed below).
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button { pendingDelete = session } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                                // Swipe right: the mantra's page (stats, tasks, sessions).
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if let mantra = session.mantra {
                                        Button { mantraToOpen = mantra } label: {
                                            Label("Mantra", systemImage: "text.quote")   // the menu's Mantras icon
                                        }
                                        .tint(.sage)
                                    }
                                }
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
        // The same centered alert as unmarking a prayer (a bottom action sheet felt out of place).
        .alert("Delete this session?",
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { session in
            Button("Delete", role: .destructive) {
                withAnimation {
                    context.delete(session)   // task progress and mantra stats recompute from what's left
                    try? context.save()
                }
                triggerSomeVibration(type: .medium)
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { session in
            Text("\(session.totalCount) counts of \(session.mantra?.name ?? session.title), \(session.startTime.formatted(date: .abbreviated, time: .shortened)). This can't be undone.")
        }
        .sheet(item: $mantraToOpen) { mantra in
            MantraEditorView(mantra: mantra)
        }
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
    /// Off inside a mantra's own page, where every row would repeat the same name: the time
    /// becomes the headline instead.
    var showsMantraName = true

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
    /// Seconds per count over the time actually spent counting — the same measure as the
    /// mantra's pace, so the two pages agree. (duration / count counted idle time after the last tap.)
    private var pace: TimeInterval? { session.secondsPerCount }   // active time only (see activeSeconds)

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                if showsMantraName {
                    Text(session.mantra?.name ?? session.title)
                        .font(.body.weight(.medium))
                } else {
                    Text(session.startTime, style: .time)
                        .font(.body.weight(.medium))
                }
                HStack(spacing: 4) {
                    if showsMantraName {
                        Text(session.startTime, style: .time)
                        Text("·")
                    }
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
                HStack(spacing: 0) {
                    Text(zikrDurationString(session.secondsPassed))
                    if let pace {
                        Text(" · ")
                        Text("\(String(format: "%.1fs", pace)) each")
                            .foregroundStyle(feelingPace ? Color.green : Color.secondary)
                            .padding(.horizontal, 6)   // fixed: a layout change mid-hold must not disturb the touch
                            .padding(.vertical, 2)
                            .overlay {
                                // While held: the pill's border fills once per count; when it
                                // closes, the tick fires and the row glows.
                                if feelingPace, let paceStart {
                                    // The fill comes straight from the clock (no animation to
                                    // reset each count, which sometimes coalesced and left the
                                    // ring sitting full for a count).
                                    TimelineView(.animation) { context in
                                        let elapsed = max(context.date.timeIntervalSince(paceStart), 0)
                                        let fill = elapsed.truncatingRemainder(dividingBy: paceInterval) / paceInterval
                                        ZStack {
                                            Capsule().stroke(Color.green.opacity(0.2), lineWidth: 1.5)
                                            Capsule()
                                                .trim(from: 0, to: fill)
                                                .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                                        }
                                    }
                                    .transition(.opacity)
                                }
                            }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: feelingPace)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        // Hold the row to feel the session's pace: a tick every `pace` seconds until the finger
        // lifts. A @GestureState resets itself on release *and* when the list takes the touch
        // for a scroll (onLongPressGesture's pressing callback ended after the first beat).
        // Hold the row to feel the session's pace. UIKit's long press, not a SwiftUI gesture:
        // scrolling comes first — any movement in the first 0.2 s fails the hold and the list
        // scrolls (SwiftUI drag / long-press versions swallowed scrolls that began on a row).
        // Once it has begun the list doesn't scroll, and it lasts until the finger lifts.
        .gesture(PaceHoldGesture { holding in
            guard let pace else { return }
            holding ? startFeelingPace(pace) : stopFeelingPace()
        })
        .onDisappear { stopFeelingPace() }
        // Each count: a soft green edge glow around the row, like the qibla map's aligned glow.
        .background { PaceEdgeGlow(beat: paceBeat).padding(-8) }
        // The whole row tints while held — the finger covers the pace text.
        .listRowBackground(feelingPace ? Color.green.opacity(0.08) : nil)
    }

    @State private var feelingPace = false
    @State private var paceBeat = 0
    @State private var paceStart: Date?
    @State private var paceInterval: TimeInterval = 1
    @State private var paceTask: Task<Void, Never>?

    private func startFeelingPace(_ pace: TimeInterval) {
        paceTask?.cancel()
        paceTask = Task { @MainActor in
            let interval = min(max(pace, 0.12), 5)
            let start = Date()
            paceInterval = interval
            paceStart = start
            withAnimation(.easeOut(duration: 0.2)) { feelingPace = true }
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            // Count zero: tick and glow the moment the hold starts, then one per fill.
            generator.impactOccurred(intensity: 0.8)
            paceBeat += 1
            // Each time the pill closes (every `interval` from `start`, the same clock the fill
            // reads): the tick and the glow, together. Sleeping to the absolute beat time keeps
            // the rhythm from drifting.
            var beat = 1
            while !Task.isCancelled {
                let next = start.addingTimeInterval(interval * Double(beat))
                try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
                guard !Task.isCancelled else { break }
                generator.impactOccurred(intensity: 0.8)
                paceBeat += 1
                beat += 1
            }
        }
    }

    private func stopFeelingPace() {
        paceTask?.cancel()
        paceTask = nil
        withAnimation(.easeOut(duration: 0.2)) { feelingPace = false }
        paceStart = nil
    }
}

/// A soft green glow hugging the row's edge that flashes once per `beat` — the same blurred
/// double stroke as the qibla map's aligned-with-Mecca edge glow, at row size.
private struct PaceEdgeGlow: View {
    let beat: Int
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.7), lineWidth: 8)
                .blur(radius: 8)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.green.opacity(0.6), lineWidth: 2)
                .blur(radius: 2)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: beat) { content, glow in
            content.opacity(glow)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.08)
                CubicKeyframe(0, duration: 0.5)
            }
        }
        .allowsHitTesting(false)
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

/// Long press that yields to scrolling: fails if the finger moves before `minimumPressDuration`.
struct PaceHoldGesture: UIGestureRecognizerRepresentable {
    var onChange: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.2
        recognizer.allowableMovement = 10
        recognizer.cancelsTouchesInView = false
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began: onChange(true)
        case .ended, .cancelled, .failed: onChange(false)
        default: break
        }
    }
}
