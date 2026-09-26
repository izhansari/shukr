//
//  SurahResponse.swift
//  shukr
//
//  Created by Izhan S Ansari on 2/4/25.
//



import SQLite3
import SwiftUI
import WidgetKit
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

    /// Verse indices in the bundled quran.sqlite run 1...6236.
    static let verseCount = 6236

    /// Returns the verse (with Arabic text) at a 1-based index in the Arabic database.
    func getVerse(at index: Int) -> Verse? {
        guard let dbArabic = dbArabic else {
            print("❌ Error: Arabic database is not available.")
            return nil
        }
        guard let cIndex = (String(index) as NSString).utf8String else {
            print("❌ Error: Failed to convert index to C string.")
            return nil
        }

        let query = "SELECT `index`, sura, aya, text FROM quran_text WHERE `index` = ?;"
        guard let result = executeQuery(in: dbArabic, query: query, cIndex: cIndex) else {
            print("❌ No Arabic verse found for index \(index).")
            return nil
        }

        return Verse(index: index, sura: result.sura, aya: result.aya, arabic: result.text)
    }

    /// Returns a random verse (with Arabic text) from the Arabic database.
    func getRandomVerse() -> Verse? {
        getVerse(at: Int.random(in: 1...Self.verseCount))
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
        fetchDailyAyah()
    }

    // One verse per calendar day: the index is drawn once and remembered with the day it was
    // drawn for, so reopening the page (or relaunching) shows the same ayah until midnight.
    private static let dailyIndexKey = "dailyAyah.index"
    private static let dailyDayKey = "dailyAyah.day"

    /// Today's verse index, drawing and storing a new one if the saved one is from another day.
    private func todaysVerseIndex() -> Int {
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        let savedIndex = defaults.integer(forKey: Self.dailyIndexKey)
        if let savedDay = defaults.object(forKey: Self.dailyDayKey) as? Date,
           calendar.isDateInToday(savedDay),
           (1...AyahDatabaseManager.verseCount).contains(savedIndex) {
            return savedIndex
        }
        let index = Int.random(in: 1...AyahDatabaseManager.verseCount)
        defaults.set(index, forKey: Self.dailyIndexKey)
        defaults.set(calendar.startOfDay(for: Date()), forKey: Self.dailyDayKey)
        return index
    }

    /// Loads today's ayah. Safe to call repeatedly: it only changes after midnight.
    func fetchDailyAyah() {
        let index = todaysVerseIndex()
        if currentAyah?.index == index { return }
        if let verse = AyahDatabaseManager.shared.getVerse(at: index) {
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

    // Animation and unlock states: the verse waits small and blurred, "from afar"; the reveal
    // brings it forward as the blur lifts, with a light blooming behind it.
    @State private var isUnlocked = false
    @State private var blurRadius: CGFloat = 12
    @State private var scale: CGFloat = 0.6
    @State private var bloom = false
    /// The surah caption flips between its name and its meaning ("an-nisaa" ⇄ "the women").
    @State private var showSurahMeaning = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showShareOptions = false
    
    // Timer publisher to update countdown every second
    @State private var timer: AnyCancellable?
    
    // For showing settings
    @State private var showingSettings = false
    
    /// Revealed once, it stays revealed for the rest of the day.
    private static let revealedDayKey = "dailyAyah.revealedDay"
    private var revealedToday: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoAyahUnrevealed") { return false }
        #endif
        return (UserDefaults.standard.object(forKey: Self.revealedDayKey) as? Date).map { Calendar.current.isDateInToday($0) } ?? false
    }

    /// Hands the revealed verse to the Daily Ayah widget (it never shows one before the reveal).
    private func publishToWidget() {
        guard revealedToday, let ayah = viewModel.currentAyah else { return }
        let surahName = viewModel.surahs.first(where: { $0.number == ayah.surah })?.englishName ?? "Surah \(ayah.surah)"
        let payload = DailyAyahWidgetPayload(day: Calendar.current.startOfDay(for: Date()),
                                             arabic: ayah.arabic, english: ayah.english,
                                             reference: "\(surahName) · \(ayah.surah):\(ayah.ayah)")
        if payload.save() { WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.ayah) }
    }

    func handleUnlock(){
        guard !isUnlocked, blurRadius > 0 else { return }
        UserDefaults.standard.set(Date(), forKey: Self.revealedDayKey)
        publishToWidget()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        withAnimation(.easeOut(duration: 1.8)) { bloom = true }
        withAnimation(.easeInOut(duration: 2.2)) {
            blurRadius = 0
            scale = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
            withAnimation(.easeInOut(duration: 0.6)) {
                isUnlocked = true
            }
        }
    }

    private var surah: Surah? {
        guard let ayah = viewModel.currentAyah else { return nil }
        return viewModel.surahs.first(where: { $0.number == ayah.surah })
    }

    /// The verse: the surah's name as a small header, the Arabic, the ayah's star marker, the
    /// meaning and the translator (tap → change translation, once revealed).
    @ViewBuilder private func verse(_ ayah: Ayah) -> some View {
        VStack(spacing: 0) {
            if let surah {
                VStack(spacing: 4) {
                    Text(surah.name)
                        .font(.custom("KFGQPCUthmanTahaNaskh", size: 20))
                        .foregroundStyle(Color.sage)
                    Text("\(showSurahMeaning ? surah.englishNameTranslation : surah.englishName) · \(surah.number):\(ayah.ayah)".lowercased())
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isUnlocked else { return }
                            triggerSomeVibration(type: .light)
                            withAnimation(.easeInOut(duration: 0.25)) { showSurahMeaning.toggle() }
                        }
                }
                .padding(.bottom, 26)
            }
            ArabicVerseText(text: ayah.arabic, size: 30,
                            color: UIColor.label.withAlphaComponent(0.92))
                .padding(.horizontal, 26)
            AyahMarker(number: ayah.ayah)
                .padding(.vertical, 22)
            Text(ayah.english)
                .font(.system(size: 17, weight: .light, design: .rounded))
                .foregroundStyle(.primary.opacity(0.78))
                .lineSpacing(5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text(ayah.translator)
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 48)
                .contentShape(Rectangle())
                .onTapGesture { if isUnlocked { showingSettings = true } }
            // Keep reading, at the end of the verse (floating at the bottom, it sat on long ones).
            if let surah {
                Link(destination: URL(string: "https://quran.com/\(surah.number)?startingVerse=\(ayah.ayah)")!) {
                    HStack(spacing: 5) {
                        Text("Continue reading on Quran.com")
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
                }
                .padding(.top, 30)
                .opacity(isUnlocked ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if isUnlocked { showingSettings = true } }
    }
    
    var body: some View {
        ZStack {
            // A soft light behind the verse: it blooms out as the ayah is revealed, then stays
            // as a faint glow that breathes (sage on white, a deeper green in dark mode).
            // A blurred circle, not a RadialGradient: the gradient reached past the view's own
            // rectangle and was cut off there, so the glow had a visible box around it (owner).
            // A blurred shape fades to nothing by itself.
            Ellipse()
                .fill(Color.sage.opacity(colorScheme == .dark ? 0.30 : 0.20))
                .frame(width: 300, height: 420)
                .blur(radius: 90)
                .scaleEffect(bloom ? 1.15 : 0.35)
                .opacity(bloom ? 1 : 0)
                .phaseAnimator([false, true]) { glow, breathing in
                    glow.opacity(isUnlocked ? (breathing ? 1 : 0.65) : 1)
                } animation: { _ in .easeInOut(duration: 4) }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Center: the verse, scrolling when it's long.
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    VStack {
                        Spacer(minLength: 120)
                        if let ayah = viewModel.currentAyah {
                            // Anchored at the top: a long verse, shrunk around its middle,
                            // waited far down the page behind the hint.
                            verse(ayah)
                                .blur(radius: blurRadius)
                                .scaleEffect(scale, anchor: .top)
                        } else {
                            Text("Loading verse…").foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 90)
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollDisabled(!isUnlocked)
                .scrollBounceBehavior(.basedOnSize)   // a verse that fits doesn't scroll at all
            }

            // Before the reveal: the whole page is the button, with a quiet hint.
            if !isUnlocked {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { handleUnlock() }
                    .ignoresSafeArea()
                VStack {
                    Spacer()
                    Text("tap to reveal today's ayah")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .phaseAnimator([0.45, 1.0]) { t, o in t.opacity(o) } animation: { _ in .easeInOut(duration: 1.8) }
                        .opacity(blurRadius > 0 && !bloom ? 1 : 0)
                        .padding(.bottom, 70)
                }
                .allowsHitTesting(false)
            }

            // Top: back, the countdown to the next verse, share.
            VStack {
                HStack(alignment: .center) {
                    Button { presentationMode.wrappedValue.dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .padding()
                    }
                    Spacer()
                    DailyAyahCountdownView(viewModel: viewModel)
                        .font(.footnote)
                    Spacer()
                    // Its sheet hangs off the page's root (see showShareOptions).
                    Button { showShareOptions = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title2)
                            .padding()
                    }
                    .buttonStyle(.plain)
                    .opacity(viewModel.currentAyah != nil ? 1 : 0)
                }
                .foregroundColor(.primary)
                .padding(.top, 10)
                .background(
                    LinearGradient(colors: [Color(UIColor.systemBackground), Color(UIColor.systemBackground).opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .padding(.bottom, -30)
                        .ignoresSafeArea()
                )
                .opacity(isUnlocked ? 1 : 0)
                Spacer()
            }
        }
        .background(Color(UIColor.systemBackground))
        .toolbar(.hidden, for:.navigationBar)
        .sheet(isPresented: $showingSettings) {
            AyahTranslationView(selectedTranslation: $viewModel.selectedTranslation, showingSettings: $showingSettings)
                .presentationDetents([.fraction(0.3)])
        }
        .sheet(isPresented: $showShareOptions) {
            if let ayah = viewModel.currentAyah {
                let surahName = viewModel.surahs.first(where: { $0.number == ayah.surah })?.englishName ?? "Surah \(ayah.surah)"
                AyahShareOptionsSheet(arabic: ayah.arabic, english: ayah.english, translator: ayah.translator,
                                      reference: "\(surahName) · \(ayah.surah):\(ayah.ayah)")
            }
        }
        .onAppear {
            if revealedToday {   // already revealed today: open straight to it
                blurRadius = 0
                scale = 1
                bloom = true
                isUnlocked = true
            }
            publishToWidget()
        }
        .onChange(of: viewModel.currentAyah?.english) { _, _ in publishToWidget() }   // translation switched
        
    }
}

/// The Arabic of the verse through UILabel: the Qur'an font's own line height is tall (room for
/// its marks), and SwiftUI's Text can only add spacing, never take it away — the lines sat far
/// apart (owner). A paragraph line-height multiple brings them together; glyphs still draw in full.
struct ArabicVerseText: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let color: UIColor
    var lineHeightMultiple: CGFloat = 0.82

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.clipsToBounds = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.baseWritingDirection = .rightToLeft
        style.lineHeightMultiple = lineHeightMultiple
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont(name: "KFGQPCUthmanTahaNaskh", size: size) ?? .systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height) + size * 0.35)   // room for the top marks
    }
}

/// The ayah's number in an eight-pointed star, like the markers between verses in a mushaf.
struct AyahMarker: View {
    let number: Int

    private var arabicDigits: String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ar_SA@numbers=arab")   // ٤٦, not 46
        return f.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(LinearGradient(colors: [.clear, Color.sage.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 0.75)
            ZStack {
                ForEach([0.0, 45.0], id: \.self) { angle in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.sage.opacity(0.75), lineWidth: 1)
                        .frame(width: 21, height: 21)
                        .rotationEffect(.degrees(angle))
                }
                Text(arabicDigits)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.sage)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 30, height: 30)
            Rectangle().fill(LinearGradient(colors: [Color.sage.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 0.75)
        }
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
            .foregroundStyle(Color.green)
            .frame(width: 15, height: 20)
            .background(Color.green.opacity(0.15).blur(radius: 2))
            .cornerRadius(5)
    }
    
    private func startTimer() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                countdown = viewModel.timeUntilNextVerse()
                // Page left open across midnight: swap in the new day's verse.
                if countdown == (0, 0, 0) { viewModel.fetchDailyAyah() }
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
