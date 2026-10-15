import SwiftUI
import SwiftData

// Your Data → a row of "On this iPhone". Each page answers "what does shukr keep about me?", never "how am I doing?"
// (owner, 2026-10-14: the stats pass read as "a crazy list"; a fresh-eyes review agreed — averages, grades, streaks,
// per-prayer and per-zikr breakdowns live on the Salah page, Insights and History). So: how many, since when, the space,
// what's kept with each record, and that part alone as a spreadsheet. Prayer photos are the photos themselves: a tap
// opens one full screen, Select picks a few to save or share. Nothing here changes or deletes anything.

enum DataKind: Hashable {
    case prayers, zikr, azkar, photos, donations, excused, settings

    var title: String {
        switch self {
        case .prayers: "Prayers"
        case .zikr: "Zikr sessions"
        case .azkar: "Azkar and daily goals"
        case .photos: "Prayer photos"
        case .donations: "Donations"
        case .excused: "Excused Mode"
        case .settings: "Your settings"
        }
    }

    /// The copy's spreadsheets for this kind (`DataExport.sheets`); settings make their own.
    var sheets: [String] {
        switch self {
        case .prayers: ["prayers.csv"]
        case .zikr: ["zikr-sessions.csv"]
        case .azkar: ["azkar.csv", "daily-goals.csv"]
        case .donations: ["donations.csv"]
        case .excused: ["excused-mode.csv"]
        case .settings: ["settings.csv"]
        case .photos: []
        }
    }
}

struct DataDetailPage: View {
    let kind: DataKind
    let sizes: YourDataPage.Sizes
    @Environment(\.modelContext) private var context
    @State private var sections: [DetailSection] = []
    @State private var sharing: [URL]?

    struct DetailSection: Identifiable {
        let id = UUID()
        var header: String? = nil
        var rows: [DetailRow]
        var footer: String? = nil
    }
    struct DetailRow: Identifiable {
        let id = UUID()
        let title: String
        var value: String = ""
        var line: String? = nil
        /// What's attached, as small symbols after the title (a zikr's photo, memo, notes; a goal's reminder).
        var icons: [String] = []
    }

    var body: some View {
        if kind == .photos {
            PhotoDataPage(sizes: sizes)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(row.title)
                                    ForEach(row.icons, id: \.self) {
                                        Image(systemName: $0).font(.caption).foregroundStyle(Color(.tertiaryLabel))
                                    }
                                }
                                if let line = row.line {
                                    Text(line).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                                }
                            }
                            Spacer(minLength: 12)
                            Text(row.value).foregroundStyle(Color(.secondaryLabel)).monospacedDigit()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    if let header = section.header { Text(header) }
                } footer: {
                    if let footer = section.footer { Text(footer) }
                }
            }
            if !sections.isEmpty {
                Section {
                    Button(action: exportThis) {
                        Label(kind.sheets.count == 1 ? "Export as a spreadsheet" : "Export as spreadsheets",
                              systemImage: "tablecells").foregroundStyle(Color.sage)
                    }
                } footer: {
                    Text("Just this part, as a .csv for Numbers, Excel or Google Sheets.")
                }
            }
        }
        .reminderPageTitle(kind.title)
        .task { sections = DataDetails.sections(kind, context, sizes) }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                FeedbackShareSheet(items: sharing) { _, _ in }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    private func exportThis() {
        var sheets = DataExport.sheets(context)
        if kind == .settings { sheets["settings.csv"] = DataDetails.csv(sections) }
        let urls = kind.sheets.compactMap { name in sheets[name].flatMap { DataExport.oneFile(name, $0) } }
        if !urls.isEmpty { sharing = urls }
    }
}

/// Each page's sections, from the store and the files. Main actor: SwiftData's objects.
@MainActor enum DataDetails {
    typealias Section = DataDetailPage.DetailSection
    typealias Row = DataDetailPage.DetailRow

    static func sections(_ kind: DataKind, _ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        switch kind {
        case .prayers: prayers(context, sizes)
        case .zikr: zikr(context, sizes)
        case .azkar: azkar(context)
        case .photos: []
        case .donations: donations()
        case .excused: excused()
        case .settings: settings()
        }
    }

    /// A page's rows as a spreadsheet (Your settings: Setting, Value).
    static func csv(_ sections: [Section]) -> String {
        func cell(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s }
        let rows = sections.flatMap { s in s.rows.map { [$0.title, $0.value].map(cell).joined(separator: ",") } }
        return (["Setting,Value"] + rows).joined(separator: "\n")
    }

    private static func n(_ v: Int) -> String { v.formatted() }
    private static func day(_ d: Date) -> String { d.formatted(.dateTime.month(.abbreviated).day().year()) }
    private static func about(_ bytes: Int64) -> String { "about " + YourDataPage.size(bytes) }

    // MARK: Prayers

    private static func prayers(_ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        let now = Date()
        // Prayers still to come today have a record too; counts are of the ones whose time has come.
        let due = rows.filter { $0.startTime <= now }
        let marked = due.filter(\.isCompleted)
        var summary = [Row(title: "Prayers recorded", value: n(due.count), line: "One record for each prayer of each day"),
                       Row(title: "Marked as prayed", value: n(marked.count))]
        if let first = rows.first { summary.append(Row(title: "Since", value: day(first.startTime))) }
        if sizes.known { summary.append(Row(title: "Space", value: about(sizes.prayers))) }

        let withPlace = marked.filter { $0.latPrayedAt != nil }.count
        let atMasjid = marked.filter(\.atMasjid).count
        let timeEdits = marked.filter(\.timeEdited).count, placeEdits = marked.filter(\.spotEdited).count
        let kept = [Row(title: "Its start and end times", value: n(due.count)),
                    Row(title: "When you marked it, and its score", value: n(marked.count)),
                    Row(title: "Where you prayed", value: n(withPlace), line: "Only when location was on"),
                    Row(title: "The masjid's name", value: n(atMasjid)),
                    Row(title: "Your changes", value: n(timeEdits + placeEdits),
                        line: "\(timeEdits) time\(timeEdits == 1 ? "" : "s"), \(placeEdits) place\(placeEdits == 1 ? "" : "s") · the first record is kept")]
        return [Section(rows: summary),
                Section(header: "Kept with each prayer", rows: kept,
                        footer: "Your scores, streaks and patterns are on the Salah page and in Insights.")]
    }

    // MARK: Zikr

    private static func zikr(_ context: ModelContext, _ sizes: YourDataPage.Sizes) -> [Section] {
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        let seconds = sessions.reduce(0) { $0 + $1.secondsPassed }
        var summary = [Row(title: "Sessions", value: n(sessions.count)),
                       Row(title: "Counted", value: n(sessions.reduce(0) { $0 + $1.totalCount })),
                       Row(title: "Time", value: time(seconds))]
        if let first = sessions.first { summary.append(Row(title: "Since", value: day(first.startTime))) }
        if sizes.known { summary.append(Row(title: "Space", value: about(sizes.zikr), line: "With your azkar's photos and voice memos")) }
        let kept = [Row(title: "When, how long and how many", value: n(sessions.count)),
                    Row(title: "The zikr it was for", value: n(sessions.filter { $0.mantra != nil }.count)),
                    Row(title: "The daily goal it counted toward", value: n(sessions.filter { $0.task != nil }.count)),
                    Row(title: "Ended by sleep mode", value: n(sessions.filter(\.endedAsleep).count))]
        return [Section(rows: summary),
                Section(header: "Kept with each session", rows: kept,
                        footer: "Each session, one by one, is in Zikr → History.")]
    }

    private static func time(_ s: Double) -> String {
        if s < 60 { return "\(Int(s)) s" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min" }
        let h = s / 3600
        return h < 10 ? String(format: "%.1f hr", h) : "\(Int(h.rounded()).formatted()) hr"
    }

    // MARK: Azkar and goals

    private static func azkar(_ context: ModelContext) -> [Section] {
        let all = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        func icons(_ z: MantraModel) -> [String] {
            [z.imageData != nil ? "photo" : nil, z.audioData != nil ? "waveform" : nil, z.notes.isEmpty ? nil : "note.text"].compactMap { $0 }
        }
        func sessions(_ z: MantraModel) -> String { "\(n(z.sessions.count)) session\(z.sessions.count == 1 ? "" : "s")" }
        let yours = all.filter { !$0.isBuiltIn }.map { Row(title: $0.name, value: sessions($0), icons: icons($0)) }
        let builtIns = all.filter(\.isBuiltIn)
        // A built-in shows here only once you've added something of yours to it.
        let added = builtIns.filter { !icons($0).isEmpty }.map { Row(title: $0.name, value: sessions($0), icons: icons($0)) }
        let goals = ((try? context.fetch(FetchDescriptor<TaskModel>())) ?? []).sorted { $0.sortOrder < $1.sortOrder }.map { t in
            Row(title: t.title, value: t.isCountMode ? "\(n(t.goal)) a day" : "\(t.goal) min a day",
                icons: [t.reminderKind != nil ? "bell" : nil, t.pausedAt != nil ? "pause.circle" : nil].compactMap { $0 })
        }
        var sections = [Section(header: "Your azkar", rows: yours.isEmpty ? [Row(title: "None of your own yet")] : yours,
                                footer: "\(builtIns.count) built-in azkar come with shukr.")]
        if !added.isEmpty {
            sections.append(Section(header: "Built-in, with your additions", rows: added))
        }
        sections.append(Section(header: "Daily goals", rows: goals.isEmpty ? [Row(title: "No daily goals yet")] : goals))
        return sections
    }

    // MARK: Donations and Excused Mode

    private static func donations() -> [Section] {
        let list = SadaqahLog.shared.donations
        var byCurrency: [String: Double] = [:]
        for d in list { byCurrency[d.currency, default: 0] += d.amount }
        var rows = [Row(title: "Donations logged", value: n(list.count))]
        if let first = list.map(\.date).min() { rows.append(Row(title: "Since", value: day(first))) }
        rows += byCurrency.keys.sorted().map { Row(title: "In all (\($0))", value: (byCurrency[$0] ?? 0).formatted(.currency(code: $0))) }
        return [Section(rows: rows,
                        footer: "Each one keeps where it went, how much, what for and your note. shukr never sees a payment.")]
    }

    private static func excused() -> [Section] {
        let ranges = Excused.ranges.sorted { $0.start > $1.start }
        let rows = ranges.map { r -> Row in
            let end = r.end.map(day) ?? "still on"
            let days = Calendar.current.dateComponents([.day], from: r.start, to: r.end ?? .now).day ?? 0
            return Row(title: "\(day(r.start)) – \(end)", value: "\(days + 1) day\(days == 0 ? "" : "s")")
        }
        return [Section(rows: rows.isEmpty ? [Row(title: "None")] : rows,
                        footer: "When Excused Mode was on. Those days are left out of your streaks and scores.")]
    }

    // MARK: Settings

    /// What's personal among the settings (where you are, how your times are worked out, your masajid, your alarm);
    /// the rest are switches that live in Settings itself.
    private static func settings() -> [Section] {
        let group = UserDefaults(suiteName: SharedStore.appGroup)
        let d = UserDefaults.standard
        let methods = [1: "University of Islamic Sciences, Karachi", 2: "Islamic Society of North America", 3: "Muslim World League",
                       4: "Umm Al-Qura University, Makkah", 5: "Egyptian General Authority of Survey",
                       7: "Institute of Geophysics, University of Tehran", 8: "Gulf Region", 9: "Kuwait", 10: "Qatar",
                       11: "Majlis Ugama Islam Singapura, Singapore", 12: "Union Organization islamic de France",
                       13: "Diyanet İşleri Başkanlığı, Turkey", 14: "Spiritual Administration of Muslims of Russia"]
        let saved = group?.object(forKey: "calculationMethod") == nil ? 2 : (group?.integer(forKey: "calculationMethod") ?? 2)
        let method = saved == 0 ? "Automatic · " + (methods[AutoMethod.effectiveMethod()] ?? "") : (methods[saved] ?? "Method \(saved)")
        let city = group?.string(forKey: "lastCityName").flatMap { $0 == "Wonderland" || $0.isEmpty ? nil : $0 } ?? "Not set"
        var alarm = "Off"
        if group?.bool(forKey: "alarmEnabled") == true {
            let mins = group?.integer(forKey: "alarmOffsetMinutes") ?? 0
            let before = group?.object(forKey: "alarmIsBefore") == nil || group?.bool(forKey: "alarmIsBefore") == true
            let fajr = group?.object(forKey: "alarmIsFajr") == nil || group?.bool(forKey: "alarmIsFajr") == true
            alarm = mins == 0 ? (fajr ? "As Fajr starts" : "As Fajr ends") : "\(mins) min \(before ? "before" : "after") Fajr \(fajr ? "starts" : "ends")"
        }
        let rows = [Row(title: "Location", value: city),
                    Row(title: "Calculation method", value: method),
                    Row(title: "Asr", value: group?.integer(forKey: "school") == 1 ? "Hanafi" : "Shafi'i"),
                    Row(title: "Fajr alarm", value: alarm),
                    Row(title: "Your masajid", value: n(MosqueFavorites.all.count), line: "Starred on the map")]
        return [Section(rows: rows,
                        footer: "Change these in Settings. They come back with an iPhone backup; Export my data copies your data, not these.")]
    }
}

// MARK: - Prayer photos

/// The photos themselves, by month, like a small Photos album (owner: "if I click on it, I don't want to select it. I
/// want to view the photo"): a tap opens it full screen; Select picks a few to save or share, and asks whether the
/// front-camera ones come too.
private struct PhotoDataPage: View {
    let sizes: YourDataPage.Sizes
    @State private var photos: [MemoryPhoto] = PrayerPhotos.all().reversed()
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var viewing: Int?
    @State private var askFront: [MemoryPhoto]?
    @State private var sharing: [URL]?

    private var months: [(title: String, photos: [(index: Int, photo: MemoryPhoto)])] {
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.dateFormat = "yyyy-MM"
        var order: [String] = [], by: [String: [(Int, MemoryPhoto)]] = [:]
        for (i, p) in photos.enumerated() {
            let m = String(p.dayKey.prefix(7))
            if by[m] == nil { order.append(m) }
            by[m, default: []].append((i, p))
        }
        return order.map { (parse.date(from: $0)?.formatted(.dateTime.month(.wide).year()) ?? $0, by[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Text("Kept inside shukr, not in your Photos library, and never synced. \(photos.count) photo\(photos.count == 1 ? "" : "s")"
                     + (sizes.known ? " · \(YourDataPage.size(sizes.photos))." : "."))
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
            }
            if photos.isEmpty {
                Text("No photos yet. After you mark a prayer, the camera in its pill takes one.").foregroundStyle(.secondary)
            }
            ForEach(months, id: \.title) { month in
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 4), spacing: 3) {
                        ForEach(month.photos, id: \.photo.key) { item in
                            PhotoCell(photo: item.photo, selecting: selecting, picked: picked.contains(item.photo.key))
                                .onTapGesture {
                                    if selecting {
                                        if picked.contains(item.photo.key) { picked.remove(item.photo.key) } else { picked.insert(item.photo.key) }
                                    } else {
                                        viewing = item.index
                                    }
                                }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3))
                } header: {
                    HStack {
                        Text(month.title)
                        Spacer()
                        Text("\(month.photos.count)").monospacedDigit()
                    }
                }
            }
        }
        .reminderPageTitle("Prayer photos")
        .toolbar {
            if !photos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { picked = [] }
                    }
                }
            }
            if selecting {
                ToolbarItem(placement: .bottomBar) {
                    Button(picked.count == photos.count ? "Select None" : "Select All") {
                        picked = picked.count == photos.count ? [] : Set(photos.map(\.key))
                    }
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    Button { save(photos.filter { picked.contains($0.key) }) } label: {
                        Label(picked.isEmpty ? "Share" : "Share \(picked.count)", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let viewing { PhotoBrowser(photos: photos, start: viewing) }
        }
        .confirmationDialog("Include the front-camera photos?", isPresented: Binding(get: { askFront != nil }, set: { if !$0 { askFront = nil } }),
                            titleVisibility: .visible) {
            if let list = askFront {
                Button("Back and front") { sharing = PhotoDataPage.urls(list, front: true) }
                Button("Back only") { sharing = PhotoDataPage.urls(list, front: false) }
            }
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                FeedbackShareSheet(items: sharing) { _, _ in }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    /// Asks about the front photos only when any of these have one.
    private func save(_ list: [MemoryPhoto]) {
        let names = PrayerPhotos.files()
        if list.contains(where: { names.contains(PrayerPhotos.url($0.key, front: true).lastPathComponent) }) {
            askFront = list
        } else {
            sharing = Self.urls(list, front: false)
        }
    }

    /// The files themselves (HEIC, older ones JPEG): Save Images in the share sheet puts them in Photos.
    static func urls(_ list: [MemoryPhoto], front: Bool) -> [URL] {
        let names = PrayerPhotos.files()
        var urls: [URL] = []
        for p in list {
            urls.append(PrayerPhotos.url(p.key, front: false))
            let f = PrayerPhotos.url(p.key, front: true)
            if front, names.contains(f.lastPathComponent) { urls.append(f) }
        }
        return urls
    }
}

/// A photo full screen: swipe between them, the prayer and day on top, its note under it, Share at the bottom.
private struct PhotoBrowser: View {
    let photos: [MemoryPhoto]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    @State private var sharing: [URL]?

    init(photos: [MemoryPhoto], start: Int) {
        self.photos = photos
        _index = State(initialValue: start)
    }

    var body: some View {
        let key = photos.indices.contains(index) ? photos[index].key : ""
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(photos.indices, id: \.self) { i in
                    BrowserPage(key: photos[i].key).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 44, height: 44)
                }
                .foregroundStyle(.white)
                Spacer()
                Text(key.isEmpty ? "" : PrayerPhotos.caption(key))
                    .font(.system(.headline, design: .rounded, weight: .regular)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 8)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 14) {
                if let note = PrayerPhotos.note(key) {
                    Text(note).font(.system(.subheadline, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).lineLimit(4).padding(.horizontal, 28)
                }
                Button {
                    sharing = PhotoDataPage.urls([photos[index]], front: true)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up").font(.system(.body, design: .rounded, weight: .medium))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Capsule().fill(.white.opacity(0.14)))
                }
                .foregroundStyle(.white)
            }
            .padding(.bottom, 12)
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                FeedbackShareSheet(items: sharing) { _, _ in }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// One photo in the browser: the back photo with the front in its corner, as every photo of a prayer shows.
private struct BrowserPage: View {
    let key: String
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)

    var body: some View {
        GeometryReader { geo in
            PrayerPhotoFace(back: images.back, front: images.front, width: min(geo.size.width - 24, geo.size.height - 220))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: key) { images = await PrayerPhotos.load(key) }
    }
}

/// A square of the grid: the back photo's small copy (Memories' cache), the prayer's name in a corner, a check when
/// picked.
private struct PhotoCell: View {
    let photo: MemoryPhoto
    let selecting: Bool
    let picked: Bool
    @State private var image: UIImage?

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(photo.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if selecting {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, picked ? Color.sage : Color.clear)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .padding(4)
                }
            }
            .opacity(selecting && !picked ? 0.75 : 1)
            .contentShape(Rectangle())
            .task {
                image = PrayerPhotos.cachedThumbnail(photo.key)
                if image == nil { image = await PrayerPhotos.thumbnail(photo.key) }
            }
            .accessibilityLabel("\(photo.name), \(photo.dayKey)")
            .accessibilityAddTraits(selecting ? (picked ? [.isSelected, .isButton] : .isButton) : .isButton)
    }
}
