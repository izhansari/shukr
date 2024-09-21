import SwiftUI

struct Session: Identifiable {
    var id = UUID()
    var title: String
    var sessionMode: Int
    var totalCount: Int
    var sessionDuration: String
    var sessionTime: Date
}

struct GPTsSessionCardView: View {
    @State private var isEditing = false
    @State private var selectedMantra = ""
    @State private var inputMantra = ""
    @State private var showSheet = false
    @Binding var session: Session
    
    // Predefined list of mantras
    @State private var predefinedMantras = ["add new recitation", "Alhamdulillah", "Subhanallah", "Astaghfirullah"]
    
    var body: some View {
        VStack {
            HStack {
                Text(session.title)
                    .font(.headline)
                Spacer()
                Image(systemName: sessionModeIcon(for: session.sessionMode))
            }
            HStack {
                Text("Count: \(session.totalCount)")
                Spacer()
                Text("Duration: \(session.sessionDuration)")
            }
            HStack {
                Text(sessionTimeFormatted(for: session.sessionTime))
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(10)
        .onTapGesture {
            showSheet = true // Show the sheet to edit the title
        }
        .sheet(isPresented: $showSheet) {
            VStack {
                Text("Select or Enter a Mantra")
                    .font(.headline)
                // Mantra Picker
                Picker("Select a Mantra", selection: $selectedMantra) {
                    ForEach(predefinedMantras, id: \.self) { mantra in
                        Text(mantra)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                
                // Or enter a custom mantra
                if(selectedMantra == "add new recitation"){
                    TextField("Or type a custom mantra", text: $inputMantra)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding()
                }
                
                Button("Save") {
                    if (inputMantra != ""){
                        session.title = inputMantra
                        predefinedMantras.append(inputMantra)
                        inputMantra = ""
                    }
                    else{
                        session.title = selectedMantra
                    }
                    showSheet = false // Close the sheet
                }.disabled(selectedMantra == "add new recitation" && inputMantra == "")
                .padding()
            }
            .padding()
        }
    }
    
    // Helper to format the session mode icon
    private func sessionModeIcon(for mode: Int) -> String {
        switch mode {
        case 0: return "infinity" // Freestyle
        case 1: return "timer"    // Timed
        case 2: return "target"   // Target Count
        default: return "circle"
        }
    }
    
    // Helper to format the session time
    private func sessionTimeFormatted(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct HistoryPage: View {
    @State private var sessions: [Session] = [
        Session(title: "Alhamdulillah", sessionMode: 0, totalCount: 100, sessionDuration: "2m 30s", sessionTime: Date()),
        Session(title: "Subhanallah", sessionMode: 1, totalCount: 200, sessionDuration: "5m 10s", sessionTime: Date())
    ]
    
    var body: some View {
        ScrollView {
            ForEach(sessions.indices, id: \.self) { index in
                GPTsSessionCardView(session: $sessions[index])
                    .padding(.horizontal)
                    .padding(.vertical, 5)
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        HistoryPage()
    }
}

#Preview {
    ContentView()
}
