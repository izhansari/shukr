//
//  SurahResponse.swift
//  shukr
//
//  Created by Izhan S Ansari on 2/4/25.
//



import SQLite3
import SwiftUI
import Combine
import Foundation

// MARK: - Model

// Top-level response from the JSON.
struct SurahResponse: Codable {
    let code: Int
    let status: String
    let data: [Surah]
}

// Model representing a single surah.
struct Surah: Codable, Identifiable {
    var id: Int { number }  // Use the surah number as the unique ID.
    let number: Int
    let name: String
    let englishName: String
    let englishNameTranslation: String
    let numberOfAyahs: Int
    let revelationType: String
}


struct Ayah: Identifiable {
    let id = UUID()
    let index: Int         // Added: the verse’s index (used to query the DB)
    let arabic: String
    let surah: Int
    let ayah: Int
    let english: String
    let translator: String
}

struct Verse {
    let index: Int
    let sura: Int
    let aya: Int
    let arabic: String
}

enum TranslationType: String, CaseIterable, Identifiable {
    // Used for the database query. Should match the SQLite file's table name (not same as file name).
    case ahmedRaza = "en_ahmedraza"
    case hilali    = "en_hilali"

    var id: String { self.rawValue }  // Conform to Identifiable for use in ForEach.

    // Used to display the name on the UI
    var displayName: String {
        switch self {
        case .ahmedRaza:
            return "Ahmed Raza Khan Barelvi"
        case .hilali:
            return "Muhammad Muhsin Khan and Muhammad Taqi-ud-Din al-Hilali"
        }
    }
}


// MARK: - Database Manager
class AyahDatabaseManager {
    static let shared = AyahDatabaseManager()

    var dbArabic: OpaquePointer?
    var translationDBs: [TranslationType: OpaquePointer] = [:]

    private init() {
        // Open the Arabic database.
        dbArabic = openDatabaseAt(filename: "quran.sqlite")
        
        // Open each translation database.
        translationDBs[.ahmedRaza] = openDatabaseAt(filename: "english_ar.sqlite")
        translationDBs[.hilali] = openDatabaseAt(filename: "english_hilali.sqlite")
        
        // Optional: Print a test query to verify the Arabic DB.
        printTableSchema()
    }
    
    private func openDatabaseAt(filename fileName: String) -> OpaquePointer? {
        guard let dbPath = Bundle.main.path(forResource: fileName, ofType: nil) else {
            print("❌ Database file \(fileName) not found in bundle."); return nil
        }

        print("📂 Database Path: \(dbPath)")

        var db: OpaquePointer?
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            print("✅ Successfully opened database: \(fileName)")
            return db
        } else {
            print("❌ Failed to open database: \(fileName). Error: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
    }

    private func printTableSchema() {
        guard let dbArabic = dbArabic else { return }
        let testQuery = "SELECT * FROM quran_text LIMIT 1;"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(dbArabic, testQuery, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW,
               let textCStr = sqlite3_column_text(statement, 3) {
                let text = String(cString: textCStr)
                print("✅ Test query successful - first text: \(text)")
            } else {
                print("❌ Test query failed - no rows found")
            }
        }
        sqlite3_finalize(statement)
    }

    // MARK: - Query Helpers

    /// A generic helper that executes a query against a given database.
    private func executeQuery(in database: OpaquePointer, query: String, cIndex: UnsafePointer<Int8>) -> (sura: Int, aya: Int, text: String)? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            print("❌ Error: Failed to prepare query: \(query)")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, cIndex, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        guard sqlite3_step(statement) == SQLITE_ROW else {
            print("❌ Error: No row returned for query: \(query)")
            return nil
        }
        
        let sura = Int(sqlite3_column_int(statement, 1))
        let aya  = Int(sqlite3_column_int(statement, 2))
        guard let textCStr = sqlite3_column_text(statement, 3) else {
            print("❌ Error: Text column is NULL for query: \(query)")
            return nil
        }
        let text = String(cString: textCStr)
        return (sura: sura, aya: aya, text: text)
    }

    // MARK: - Public Functions

    /// Returns a random verse (with Arabic text) from the Arabic database.
    func getRandomVerse() -> Verse? {
        guard let dbArabic = dbArabic else {
            print("❌ Error: Arabic database is not available.")
            return nil
        }
        
        let randomIndex = Int.random(in: 1...6236)
        let indexString = String(randomIndex)
        
        guard let cIndex = (indexString as NSString).utf8String else {
            print("❌ Error: Failed to convert index to C string.")
            return nil
        }
        
        let query = "SELECT `index`, sura, aya, text FROM quran_text WHERE `index` = ?;"
        guard let result = executeQuery(in: dbArabic, query: query, cIndex: cIndex) else {
            print("❌ No Arabic verse found for index \(randomIndex).")
            return nil
        }
        
        return Verse(index: randomIndex, sura: result.sura, aya: result.aya, arabic: result.text)
    }

    /// Returns a translation for the given verse index and translation option.
    func getTranslation(for verseIndex: Int, translation: TranslationType) -> String? {
        guard let db = translationDBs[translation] else {
            print("❌ Error: Database for \(translation.rawValue) is not available.")
            return nil
        }
        
        let indexString = String(verseIndex)
        guard let cIndex = (indexString as NSString).utf8String else {
            print("❌ Error: Failed to convert index to C string.")
            return nil
        }
        
        // Since the database schema is the same, we can use the same query structure.
        let query = "SELECT `index`, sura, aya, text FROM \(translation.rawValue) WHERE `index` = ?;"
        guard let result = executeQuery(in: db, query: query, cIndex: cIndex) else {
            print("❌ No translation found for index \(verseIndex) in \(translation.rawValue).")
            return nil
        }
        
        return result.text
    }

}


// MARK: - ViewModel

import SwiftUI
import Combine

final class DailyAyahViewModel: ObservableObject {
    
    // Use the enum type directly.
    @Published var selectedTranslation: TranslationType = .hilali {
        didSet {
            if let current = currentAyah {
                fetchTranslation(for: current.index)
            }
        }
    }
    
    @Published var currentAyah: Ayah? = nil
    @Published var surahs: [Surah] = []
    
    init() {
        loadSurahs()
        fetchRandomAyah()
    }
    
    func fetchRandomAyah() {
        if let verse = AyahDatabaseManager.shared.getRandomVerse() {
            // Use the selectedTranslation enum directly.
            let translationType = selectedTranslation
            let englishText = AyahDatabaseManager.shared.getTranslation(for: verse.index, translation: translationType) ?? "No translation found."
            
            // Build the Ayah model.
            let newAyah = Ayah(index: verse.index,
                               arabic: verse.arabic,
                               surah: verse.sura,
                               ayah: verse.aya,
                               english: englishText,
                               translator: translationType.displayName)
            DispatchQueue.main.async {
                self.currentAyah = newAyah
            }
        } else {
            DispatchQueue.main.async {
                self.currentAyah = nil
            }
        }
    }
    
    func fetchTranslation(for verseIndex: Int) {
        let translationType = selectedTranslation
        if let englishText = AyahDatabaseManager.shared.getTranslation(for: verseIndex, translation: translationType),
           let current = currentAyah {
            let updatedAyah = Ayah(index: current.index,
                                   arabic: current.arabic,
                                   surah: current.surah,
                                   ayah: current.ayah,
                                   english: englishText,
                                   translator: translationType.displayName)
            DispatchQueue.main.async {
                self.currentAyah = updatedAyah
            }
        }
    }
    
    // Computes the time remaining until midnight (when the next verse becomes available)
    func timeUntilNextVerse() -> (hours: Int, minutes: Int, seconds: Int) {
        let now = Date()
        let calendar = Calendar.current
        if let nextMidnight = calendar.nextDate(after: now, matching: DateComponents(hour:0, minute:0, second:0), matchingPolicy: .strict) {
            let diff = calendar.dateComponents([.hour, .minute, .second], from: now, to: nextMidnight)
            return (diff.hour ?? 0, diff.minute ?? 0, diff.second ?? 0)
        }
        return (0, 0, 0)
    }
    
    func loadSurahs() -> [Surah] {
        guard let url = Bundle.main.url(forResource: "Surahs", withExtension: "json") else {
            print("❌ surahs.json not found in bundle.")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let response = try JSONDecoder().decode(SurahResponse.self, from: data)
            self.surahs = response.data
            return self.surahs
        } catch {
            print("❌ Error decoding surahs.json: \(error)")
            return []
        }
    }
}



// MARK: - Share Sheet

struct AyahShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> some UIViewController {
        let controller = UIActivityViewController(activityItems: activityItems,
                                                  applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}

// MARK: - Main ContentView

struct SurahHeaderView: View {
    let surah: Surah
    let ayahNumber: Int
    
    @State private var showTranslation = false

    var body: some View {
        HStack(spacing: 3) {
            // This text shows either the englishName or the englishNameTranslation.
            Text("\(showTranslation ? surah.englishNameTranslation : surah.englishName)")
            Text("(\(surah.number):\(ayahNumber))")
        }
        .onTapGesture {
            withAnimation {
                showTranslation.toggle()
            }
        }
    }
}

struct DailyAyahView: View {
    @StateObject private var viewModel = DailyAyahViewModel()
    @Environment(\.presentationMode) var presentationMode

    // Animation and unlock states
    @State private var isUnlocked = false
    @State private var blurRadius: CGFloat = 10
    @State private var scale: CGFloat = 0.5
    @State private var showShareSheet = false
    
    // Timer publisher to update countdown every second
    @State private var timer: AnyCancellable?
    
    // For showing settings
    @State private var showingSettings = false
    
    func handleUnlock(){
        withAnimation(.easeInOut(duration: 2)) {
            blurRadius = 0
            scale = 0.7
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isUnlocked = true
            }
        }
    }
    
    var body: some View {
        ZStack{
            // Top Bar
            VStack(){
                HStack(alignment: .center) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .padding()
                    }
                    Spacer()
                    // Countdown timer at the top
                    DailyAyahCountdownView(viewModel: viewModel)
                        .font(.footnote)
                    Spacer()
                    if let ayah = viewModel.currentAyah {
                        Button(action: {
                            showShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .padding()
                        }
                        .sheet(isPresented: $showShareSheet) {
                            // Prepare text to share.
                            let shareText = """
                        \(ayah.arabic)
                        \(ayah.surah):\(ayah.ayah)
                        
                        \(ayah.english)
                        — \(ayah.translator)
                        """
                            AyahShareSheet(activityItems: [shareText])
                                .presentationDetents([.medium]) // Custom detents
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundColor(.primary)
                .padding(.top, 10)
                .opacity(isUnlocked ? 1 : 0) // Only show once unlocked, if desired.
                .sheet(isPresented: $showingSettings) {
                    AyahTranslationView(selectedTranslation: $viewModel.selectedTranslation, showingSettings: $showingSettings)
                        .presentationDetents([.fraction(0.3)/*, .height(100)*/]) // Custom detents
                }
                Spacer()
            }
            
            // Center Items
            VStack(){
                Spacer()
                
                // Verse display area
                if let ayah = viewModel.currentAyah {
                    VStack(spacing: 10) {
                        Text(ayah.arabic)
                            .font(.custom("KFGQPCUthmanTahaNaskh.ttf", size: 36))
                            .lineLimit(nil)
                            .lineSpacing(5) // Adjust this value to increase or decrease line spacing
                            .padding()
                        
                        Group{
                            Text(ayah.english)
                                .font(.title3)
                                .padding(.horizontal)
                            
                            Text("— \(ayah.translator)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .onTapGesture {
                            if isUnlocked{
                                showingSettings = true
                            }
                            else {
                                handleUnlock()
                            }
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    .blur(radius: blurRadius)
                    .scaleEffect(scale)
                    // Tapping triggers the unlock animation if not already unlocked.
                    .onTapGesture {
                        handleUnlock()
                    }
                } else {
                    Text("Loading verse...")
                }
                
                Spacer()
            }
            
            // Bottom Items
            VStack(spacing: 20) {
                
                Spacer()
                
                ZStack(){
                    HStack{
                        Spacer()
                        if let ayah = viewModel.currentAyah, let surah = viewModel.surahs.first(where: { $0.number == ayah.surah }) {
                            // Place the header at the top.
                            VStack{
                                SurahHeaderView(surah: surah, ayahNumber: ayah.ayah)
                                    .font(.callout)
                                    .foregroundColor(.secondary)
//                                    .scaleEffect(scale)
                                let url = URL(string: "https://quran.com/\(surah.number)?startingVerse=\(ayah.ayah)")!
                                
//                                let url = URL(string: "https://quran.com/\(surah.number)/\(ayah.ayah)")!
                                
                                Link("Continue reading on Quran.com", destination: url)
                                    .font(.footnote)
                            }
                        } else {
                            Text("Surah data not found.")
                        }
                        Spacer()
                    }
                    .opacity(isUnlocked ? 1 : 0)
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .toolbar(.hidden, for:.navigationBar)
        
    }
}

// MARK: - Settings View

struct AyahTranslationView: View {
    @Binding var selectedTranslation: TranslationType
    @Binding var showingSettings: Bool
    
    var body: some View {
        NavigationView {
            VStack{
                Form {
                    Section(header: Text("Select Translation")) {
                        Picker("Translation", selection: $selectedTranslation) {
                            ForEach(TranslationType.allCases) { translation in
                                Text(translation.displayName)
                                    .tag(translation)
                            }
                        }
                        .pickerStyle(.automatic)
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                
            }
        }
    }
}



// MARK: - Helper Countdown View
import SwiftUI
import Combine

struct DailyAyahCountdownView: View {
    @ObservedObject var viewModel: DailyAyahViewModel
    @State private var timer: AnyCancellable?
    @State private var countdown: (hours: Int, minutes: Int, seconds: Int) = (0, 0, 0)
    @State private var countdownText: String = ""
    @State private var hoursText: String = ""
    @State private var minText: String = ""
    @State private var secText: String = ""
    
    var body: some View {
        VStack {
            Text("Next Verse in:")
                .font(.caption)
                .padding(.top)
            
            HStack(spacing: 6) {
                timePlace(val: countdown.hours, text: "hours")
                Text(":")
                timePlace(val: countdown.minutes, text: "min")
                Text(":")
                timePlace(val: countdown.seconds, text: "sec")
            }
            .font(.caption)
        }
        .onAppear(perform: startTimer)
    }

    private func timePlace(val: Int, text: String) -> some View {
        VStack(spacing: 2){
            HStack(spacing: 6){
                singleDigitBox(value: val / 10) // Tens place
                singleDigitBox(value: val % 10) // Ones place
            }
            Text(text)
                .font(.system(size: 8))
        }
    }
    
    private func singleDigitBox(value: Int) -> some View {
        Text("\(value)")
            .fontWeight(.bold)
            .frame(width: 15, height: 20)
            .background(Color(.secondarySystemFill).blur(radius: 2))
            .cornerRadius(5)
    }
    
    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                countdown = viewModel.timeUntilNextVerse()
            }
    }

}

struct CountdownView_Previews: PreviewProvider {
    static var previews: some View {
        DailyAyahCountdownView(viewModel: DailyAyahViewModel())
    }
}

// MARK: - Preview

struct AyahApp_Previews: PreviewProvider {
    static var previews: some View {
        DailyAyahView()
    }
}
