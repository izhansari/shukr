import SwiftUI
import SwiftData

// MARK: - DuaPageView

struct DuaPageView: View {
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DuaModel.date, order: .reverse) private var duaItems: [DuaModel]

    @State private var searchText = ""
    @State private var showingEditDuaSheet = false
    @State private var dummyBool = false
    @State private var selectedDua: DuaModel? = nil
    @State private var initialSearchQueryForEditDuaView: String? = nil

//    @Binding var showingDuaPageBool: Bool

    @FocusState private var isSearchFieldFocused: Bool // Added focus state for search field

    var filteredDuas: [DuaModel] {
        if searchText.isEmpty {
            return duaItems
        } else {
            return duaItems.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.duaBody.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private func cancelSearch(){
        triggerSomeVibration(type: .light)
        searchText = ""
        isSearchFieldFocused = false // Dismiss keyboard and remove focus
    }
    
    private func exitPage() {
        // Close the Dua page and keyboard
//        triggerSomeVibration(type: .light)
//        isSearchFieldFocused = false
//        searchText = ""
//        dismiss()
        dismissKeyboard()
        withAnimation(.spring(duration: 0.3)) {
            sharedState.navPosition = sharedState.cameFromNavPosition
        }
    }

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium // Adjust to the preferred date style
        formatter.timeStyle = .short // Adjust to the preferred time style
        return formatter
    }()
    
    var body: some View {
        VStack {
            
            // Top Bar (Search, Cancel, Dismiss)
            HStack {
                // 1. Search
                TextField("Search Notes", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isSearchFieldFocused) // Bind focus state
                // 2. Cancel
                if !searchText.isEmpty {
                    Button(action: {
                        cancelSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.systemRed).opacity(0.8))
                    }
                }
                // 3. Dismiss
                else {
                    Button(action: {
                        exitPage()
                    }) {
                        Image(systemName: "chevron.right") // Standard back arrow
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding([.horizontal, .bottom])
            
            // Dua List
            if duaItems.isEmpty {
                Spacer()
                VStack{
                    Text("We all forget and need reminders..")
                        .padding()
                    Text("use this space to record your duas, notes from khutbahs, ayahs, or any personal reflections")
                        .multilineTextAlignment(.center)
                        .font(.footnote)
                        .frame(width: 300)
                    Button(action: {
                        dummyBool = true
                    }) {
                        Image(systemName: "chevron.right") // Standard back arrow
                            .foregroundColor(.gray)
                    }
                }
                .foregroundColor(.gray)
                Spacer()
            } else if filteredDuas.isEmpty {
                Spacer()
                Text("No matching notes found.")
                    .foregroundColor(.gray)
                Spacer()
            } else {
                List {
                    ForEach(filteredDuas) { dua in
                        // Use a regular view and add an onTapGesture
                        HStack{
                            VStack(alignment: .leading) {
                                highlightedText(for: dua.title, searchText: searchText)
                                    .font(.headline)
                                Text(dateFormatter.string(from: dua.date))
                                    .font(.subheadline)
                                    .fontWeight(.light)
                                    .foregroundColor(.gray)
                                highlightedText(for: String(dua.duaBody.prefix(100)) + (dua.duaBody.count > 100 ? "..." : ""), searchText: searchText)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            .padding()
                            Spacer()
                        }
                        .contentShape(Rectangle()) // Make the entire cell tappable
                        .onTapGesture {
                            print("Tapped on dua: \(dua.title)")
                            triggerSomeVibration(type: .light)
                            selectedDua = dua
                            initialSearchQueryForEditDuaView = searchText
                            // Present the sheet after updating selectedDua
                            showingEditDuaSheet = true
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                triggerSomeVibration(type: .light)
                                deleteDua(dua: dua)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            // Share option
                            ShareLink(item: dua.title + ":\n\n" + dateFormatter.string(from: dua.date) + "\n\n" + dua.duaBody) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                        .listRowInsets(EdgeInsets()) // Remove default insets
                    }
                    .onDelete(perform: deleteDuas)
                }
                .shadow(color: .black.opacity(0.1), radius: 10)
                .scrollContentBackground(.hidden)
            }
            
            // Add Dua Button
            HStack {
                Spacer()
                Button(action: {
                    triggerSomeVibration(type: .light)
                    print("Add Dua button tapped")
                    selectedDua = nil
                    initialSearchQueryForEditDuaView = nil
                    showingEditDuaSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                            .resizable()
                            .frame(width: 15, height: 15)
                        Text("Add Note")
                    }
                    .frame(height: 40)
                    .font(.subheadline)
                    .foregroundColor(.green.opacity(0.7))
                }
                Spacer()
            }
        }
        
        //this is the original. we want to change it to a navigation destination.
        .fullScreenCover(isPresented: $showingEditDuaSheet, onDismiss: {
            selectedDua = nil
            initialSearchQueryForEditDuaView = nil
        }) {
            EditDuaView(
                dua: $selectedDua,
                onSave: { newTitle, newBody in
                    if let dua = selectedDua {
                        // Update existing dua
                        dua.title = newTitle
                        dua.duaBody = newBody
                        dua.date = Date()
                    } else {
                        // Create new dua
                        let newDua = DuaModel(title: newTitle, duaBody: newBody, date: Date())
                        context.insert(newDua)
                    }
                    // Save changes
                    do {
                        try context.save()
                    } catch {
                        print("Failed to save dua: \(error)")
                    }
                    showingEditDuaSheet = false // Dismiss the sheet
                },
                initialSearchQuery: initialSearchQueryForEditDuaView // Pass the search query
            )
            .interactiveDismissDisabled(true) // Disable swipe-to-dismiss
        }

        //this works
        //        .navigationDestination(isPresented: $showingEditDuaSheet){
        //            DailyAyahView()
        //        }

        //this doesnt work.
//        .navigationDestination(isPresented: $showingEditDuaSheet){
//            EditDuaView(
//                dua: $selectedDua,
//                onSave: { newTitle, newBody in
//                    if let dua = selectedDua {
//                        // Update existing dua
//                        dua.title = newTitle
//                        dua.duaBody = newBody
//                        dua.date = Date()
//                    } else {
//                        // Create new dua
//                        let newDua = DuaModel(title: newTitle, duaBody: newBody, date: Date())
//                        context.insert(newDua)
//                    }
//                    // Save changes
//                    do {
//                        try context.save()
//                    } catch {
//                        print("Failed to save dua: \(error)")
//                    }
//                    showingEditDuaSheet = false // Dismiss the sheet
//                },
//                initialSearchQuery: initialSearchQueryForEditDuaView // Pass the search query
//            )
//            .interactiveDismissDisabled(true) // Disable swipe-to-dismiss
//            .onDisappear {
//                selectedDua = nil
//                initialSearchQueryForEditDuaView = nil
//            }
//            .toolbar(.hidden, for: .navigationBar)
//        }


    }

    // Delete function
    private func deleteDuas(at offsets: IndexSet) {
        for index in offsets {
            let dua = filteredDuas[index]
            context.delete(dua)
        }
        do {
            try context.save()
        } catch {
            print("Failed to delete dua: \(error)")
        }
    }
    
    private func deleteDua(dua: DuaModel) {
        context.delete(dua)
        do {
            try context.save()
        } catch {
            print("Failed to delete dua: \(error)")
        }
    }

    // Function to highlight search text in results
    func highlightedText(for text: String, searchText: String) -> Text {
        guard !searchText.isEmpty else { return Text(text) }

        let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: searchText), options: .caseInsensitive)
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []

        var result = Text("")
        var currentIndex = text.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let beforeMatch = text[currentIndex..<matchRange.lowerBound]
            let matchedText = text[matchRange]

            result = result + Text(beforeMatch) + Text(matchedText).bold().foregroundColor(.blue)
            currentIndex = matchRange.upperBound
        }

        let remainingText = text[currentIndex..<text.endIndex]
        result = result + Text(remainingText)

        return result
    }
}

// MARK: - EditDuaView

struct EditDuaView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) var dismiss
//    @Environment(\.presentationMode) var presentationMode

    @Binding var dua: DuaModel?
    @State private var title: String = ""
    @State private var duaBody: String = ""

    @State private var originalTitle: String = ""
    @State private var originalDuaBody: String = ""

    private var theyMadeChanges: Bool {
        return title != originalTitle || duaBody != originalDuaBody
    }

    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool

//    @State private var showingDiscardChangesAlert = false

    var onSave: (String, String) -> Void

    // New state variables for search
    @State private var showingSearchBar = false
    @State private var searchQuery = ""
    @State private var currentOccurrenceIndex = 0
    @State private var totalOccurrences = 0
    @State private var matches: [NSRange] = []

    // Computed property to control whether the note is editable
    var isSearching: Bool {
        showingSearchBar
    }

    var isNewDua: Bool {
        return dua == nil
    }

    init(dua: Binding<DuaModel?>, onSave: @escaping (String, String) -> Void, initialSearchQuery: String? = nil) {
        self._dua = dua
        self.onSave = onSave

        // Initialize search if provided
        if let searchQuery = initialSearchQuery, !searchQuery.isEmpty {
            self._searchQuery = State(initialValue: searchQuery)
            self._showingSearchBar = State(initialValue: true)
        }
    }

    var body: some View {
        VStack {
            // Top HStack for navigation controls
            HStack {
                
                // Button to save or close.
                Button(action: {
                    triggerSomeVibration(type: .light)
                    if (theyMadeChanges && !title.isEmpty && !duaBody.isEmpty){
                        onSave(title, duaBody)
                    }
                    if (title.isEmpty && duaBody.isEmpty), let dua = dua{
                        context.delete(dua)
                    }
                    dismiss()
                }) {
                    Image(systemName:  "chevron.left")
                        .foregroundStyle( .gray )
                        .frame(width: 30, height: 30)
                }
                
                if showingSearchBar {
                    // search bar
                    HStack(spacing: 5) {
                        TextField("Search", text: $searchQuery)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(5)
                            .background(Color(.systemGray5))
                            .cornerRadius(8)
                            .onChange(of: searchQuery) {
                                calculateMatches()
                                currentOccurrenceIndex = 0
                            }
                            .submitLabel(.done)
                            .focused($isSearchFieldFocused) // Allows keyboard dismissal

                        HStack(spacing: 4) {
                            
                            Button(action: {
                                triggerSomeVibration(type: .light)
                                isSearchFieldFocused = false // Dismiss keyboard
                                showingSearchBar = false
                                searchQuery = ""
                                matches = []
                                totalOccurrences = 0
                                currentOccurrenceIndex = 0
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                            }.padding(.trailing, 4)
                            
                            Text("\(min(currentOccurrenceIndex + 1, totalOccurrences))/\(totalOccurrences)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            Button(action: {
                                triggerSomeVibration(type: .light)
                                isSearchFieldFocused = false // Dismiss keyboard
                                moveToPreviousOccurrence()
                            }) {
                                Image(systemName: "chevron.up")
                            }
                            .disabled(totalOccurrences == 0)

                            Button(action: {
                                triggerSomeVibration(type: .light)
                                isSearchFieldFocused = false // Dismiss keyboard
                                moveToNextOccurrence()
                            }) {
                                Image(systemName: "chevron.down")
                            }
                            .disabled(totalOccurrences == 0)
                            
                        }
                        .padding(.trailing, 3)
                    }
                    .frame(height: 30)
                } else if !showingSearchBar {
                    Spacer()
                    
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }) {
                        Text("Done")
                            .foregroundStyle( .gray )
                            .padding(.trailing, 3)
                    }
                    .opacity(isBodyFocused || isTitleFocused ? 1 : 0)
                }

                
//                Spacer()

            }
            .frame(height: 44)
            .padding()

            // Content for editing the dua
            VStack(spacing: 0) { // Adjusted spacing
                TextField("Your New Dua Title", text: $title)
                    .font(.title2)
                    .padding()
                    .focused($isTitleFocused)
                    .disabled(isSearching)

                Divider() // Added divider to separate title and body

                // Replace TextEditor with HighlightingTextView
                HighlightingTextView(
                    text: $duaBody,
                    searchQuery: searchQuery,
                    matches: matches,
                    currentOccurrenceIndex: currentOccurrenceIndex,
                    isSearching: isSearching // Pass isSearching to control editability
                )
                .focused($isBodyFocused)
                .frame(maxHeight: .infinity)
                .padding()
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.gray),
                    alignment: .top
                )
            }
            .onDisappear {
                isBodyFocused = false
                isTitleFocused = false
            }
            Spacer()
        }
        .onAppear {
            // Initialize the state variables when the view appears
            initializeState()
            if showingSearchBar {
                calculateMatches()
            }
        }
        .onChange(of: dua) {
            // Update state variables when dua changes
            initializeState()
        }
        .onChange(of: duaBody) {
            if showingSearchBar {
                calculateMatches()
            }
        }
    }

    func initializeState() {
        if let dua = dua {
            title = dua.title
            duaBody = dua.duaBody
            originalTitle = dua.title
            originalDuaBody = dua.duaBody
        } else {
            title = ""
            duaBody = ""
            originalTitle = ""
            originalDuaBody = ""
        }
    }

    func calculateMatches() {
        let text = duaBody
        let search = searchQuery.lowercased()
        guard !search.isEmpty else {
            matches = []
            totalOccurrences = 0
            currentOccurrenceIndex = 0
            return
        }
        let pattern = NSRegularExpression.escapedPattern(for: search)
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: text.utf16.count)
            let matchResults = regex.matches(in: text.lowercased(), options: [], range: range)
            matches = matchResults.map { $0.range }
            totalOccurrences = matches.count
            if currentOccurrenceIndex >= totalOccurrences {
                currentOccurrenceIndex = 0
            }
        } catch {
            matches = []
            totalOccurrences = 0
            currentOccurrenceIndex = 0
        }
    }

    // Functions to move between occurrences
    func moveToNextOccurrence() {
        if totalOccurrences > 0 {
            currentOccurrenceIndex = (currentOccurrenceIndex + 1) % totalOccurrences
        }
    }

    func moveToPreviousOccurrence() {
        if totalOccurrences > 0 {
            currentOccurrenceIndex = (currentOccurrenceIndex - 1 + totalOccurrences) % totalOccurrences
        }
    }
}

// MARK: - HighlightingTextView

struct HighlightingTextView: UIViewRepresentable {
    @Binding var text: String
    var searchQuery: String
    var matches: [NSRange]
    var currentOccurrenceIndex: Int
    var isSearching: Bool

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = !isSearching
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: UIFont.labelFontSize)
        textView.isScrollEnabled = true
        textView.backgroundColor = UIColor.clear
        textView.textContainerInset = UIEdgeInsets.zero
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardDismissMode = .interactive // Allow interactive dismissal
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.isEditable = !isSearching

        // Apply highlights
        let attributedText = NSMutableAttributedString(string: text)
        let range = NSRange(location: 0, length: text.utf16.count)
        attributedText.addAttribute(.foregroundColor, value: UIColor.label, range: range)
        attributedText.addAttribute(.font, value: UIFont.systemFont(ofSize: UIFont.labelFontSize), range: range)

        if !searchQuery.isEmpty {
            for (index, matchRange) in matches.enumerated() {
                if index == currentOccurrenceIndex {
                    // Highlight the current occurrence differently
                    attributedText.addAttribute(.backgroundColor, value: UIColor.systemOrange, range: matchRange)
                    // Scroll to the selected range
                    DispatchQueue.main.async {
                        uiView.selectedRange = matchRange
                        uiView.scrollRangeToVisible(matchRange)
                    }
                } else {
                    attributedText.addAttribute(.backgroundColor, value: UIColor.systemYellow, range: matchRange)
                }
            }
        }

        uiView.attributedText = attributedText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: HighlightingTextView

        init(_ parent: HighlightingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
    }
}

// MARK: - Preview

#Preview {
//    @Previewable @State var showingDuaPageBool = true
    DuaPageView(/*showingDuaPageBool: $showingDuaPageBool*/)
}
