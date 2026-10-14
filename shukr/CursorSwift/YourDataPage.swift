import SwiftUI
import SwiftData

// Settings → Your Data (owner, 2026-10-14): what shukr keeps, that it's private and on this iPhone only, whether it's
// backed up, and a copy of it all to keep. Built like the three "Your …" pages (ReminderPageParts.swift): a status row,
// a bar in parts, two "why" rows opening an ⓘ card, then the breakdown — a utility page, not a branded one.
//
// The facts it states (checked 2026-10-14): no network code in shukr (no account, no server, no analytics); Apple Maps is
// asked for mosques and place names; nothing is excluded from the iPhone's backup and nothing syncs (no CloudKit);
// prayer photos live in Application Support, not the Photos library.

struct YourDataPage: View {
    @Environment(\.modelContext) private var context
    @State private var counts = Counts()
    @State private var sizes = Sizes()
    @State private var why: Why?
    @State private var withMedia = true
    @State private var exporting = false
    @State private var exported: URL?
    @State private var failed = false
    enum Why { case privacy, backup }

    struct Counts {
        var prayers = 0, marked = 0, sessions = 0, azkar = 0, goals = 0, photos = 0, donations = 0, excused = 0
        var firstMarked: Date?
        var zikrSeconds: Double = 0
    }
    struct Sizes {
        var records: Int64 = 0, photos: Int64 = 0, other: Int64 = 0
        var total: Int64 { records + photos + other }
        var known = false
    }

    var body: some View {
        List {
            Section {
                ReminderPageStatus(good: true, title: "Private, and only on this iPhone",
                                   subtitle: "No account and no server: nothing you do in shukr is sent to us or anyone")
                sizeBar
                ReminderWhyLink(symbol: "lock", title: "What stays private") { why = .privacy }
                ReminderWhyLink(symbol: "icloud", title: "Is it backed up?") { why = .backup }
            }
            Section {
                row("checkmark.circle", "Prayers", prayersLine)
                row("circle.hexagonpath", "Zikr sessions", sessionsLine)
                row("books.vertical", "Azkar and daily goals", "\(counts.azkar) of yours · \(counts.goals) goal\(counts.goals == 1 ? "" : "s")")
                row("camera", "Prayer photos", counts.photos == 0 ? "None yet"
                    : "\(counts.photos) photo\(counts.photos == 1 ? "" : "s")" + (sizes.known ? " · \(Self.size(sizes.photos))" : ""))
                if counts.donations > 0 { row("gift", "Donations you logged", "\(counts.donations)") }
                if counts.excused > 0 { row("pause.circle", "Excused Mode", "\(counts.excused) time\(counts.excused == 1 ? "" : "s")") }
                row("gearshape", "Your settings", "Location, prayer times, reminders and looks")
            } header: { Text("On this iPhone") }
            Section {
                Toggle(isOn: $withMedia) {
                    Text("Include photos and voice memos")
                }
                .tint(Color.sage)
                Button(action: export) {
                    HStack {
                        Spacer()
                        if exporting { ProgressView().padding(.trailing, 6) }
                        Label(exporting ? "Making your copy…" : "Export my data", systemImage: "square.and.arrow.up")
                            .font(.system(.body, design: .rounded, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(Color.sage)
                }
                .disabled(exporting)
            } header: {
                Text("A copy for you")
            } footer: {
                Text("A .zip of spreadsheets you can open in Numbers or Excel: your prayers, zikr sessions, azkar, goals and donations. It only goes where you send it.")
            }
        }
        .reminderPageTitle("Your Data")
        .task { load() }
        .sheet(isPresented: Binding(get: { exported != nil }, set: { if !$0 { exported = nil } })) {
            if let exported {
                FeedbackShareSheet(items: [exported]) { _, _ in }
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
        .alert("Couldn't make the copy", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data is safe. Try again in a moment, or without photos if space is short.")
        }
        .infoModal(isPresented: Binding(get: { why == .privacy }, set: { if !$0 { why = nil } }),
                   title: "What stays private", symbol: "lock") {
            ReminderExplainer(head: "Everything you do in shukr stays on this iPhone.", points: [
                .init(big: "No account, no server", small: "shukr has nowhere to send your data. Your prayers, zikr, photos and notes are never sent to us or anyone else.", symbol: "lock.shield", warn: false),
                .init(big: "Your location", small: "Used on your phone for prayer times, the qibla and where you prayed. Looking for mosques or a place's name asks Apple Maps, as the Maps app does.", symbol: "location", warn: false),
                .init(big: "Your photos", small: "Prayer photos stay inside shukr, not in your Photos library, and they're never synced.", symbol: "photo.on.rectangle", warn: false),
                .init(big: "Only when you ask", small: "A copy is made only when you tap Export, and it goes only where you send it.", symbol: "square.and.arrow.up", warn: false),
            ])
        }
        .infoModal(isPresented: Binding(get: { why == .backup }, set: { if !$0 { why = nil } }),
                   title: "Is it backed up?", symbol: "icloud") {
            ReminderExplainer(head: "shukr is part of your iPhone's own backup.", points: [
                .init(big: "With iCloud Backup on", small: "shukr's data is in it, photos too. Check in Settings → your name → iCloud → iCloud Backup.", symbol: "icloud", warn: false),
                .init(big: "On a new iPhone", small: "Set it up from that backup and shukr comes back with your history, photos and goals.", symbol: "iphone", warn: false),
                .init(big: "Deleting shukr deletes it", small: "Removing the app removes its data from this iPhone too. Backups made before still have it.", symbol: "trash", warn: false, neutral: true),
                .init(big: "Your own copy", small: "Export my data saves it all as spreadsheets you can keep anywhere.", symbol: "square.and.arrow.up", warn: false),
            ])
        }
    }

    private func row(_ symbol: String, _ title: String, _ line: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color(.secondaryLabel)).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(line).font(.footnote).foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(.vertical, 2)
    }

    private var prayersLine: String {
        guard counts.marked > 0 else { return "None marked yet" }
        let since = counts.firstMarked.map { " since " + $0.formatted(.dateTime.month(.abbreviated).year()) } ?? ""
        return "\(counts.marked.formatted()) marked\(since)"
    }

    private var sessionsLine: String {
        guard counts.sessions > 0 else { return "None yet" }
        let hours = counts.zikrSeconds / 3600
        let time = hours >= 1 ? "\(Int(hours.rounded()).formatted()) hour\(Int(hours.rounded()) == 1 ? "" : "s")"
            : counts.zikrSeconds < 60 ? "under a minute" : "\(Int((counts.zikrSeconds / 60).rounded())) min"
        return "\(counts.sessions.formatted()) sessions · \(time)"
    }

    /// The space it takes, in parts — as the "Your …" pages show their room.
    private var sizeBar: some View {
        // In KB so a small part still shows; the key says each part's size.
        let kb = { (b: Int64) in Int(b / 1000) }
        return ReminderSlotsBar(caption: sizes.known ? "\(Self.size(sizes.total)) on this iPhone" : "Measuring…",
                                limit: max(kb(sizes.total), 1),
                                parts: [.init(count: kb(sizes.records), color: Color.sage, label: "Records", value: Self.size(sizes.records)),
                                        .init(count: kb(sizes.photos), color: Color(.systemTeal), label: "Photos", value: Self.size(sizes.photos)),
                                        .init(count: kb(sizes.other), color: Color(.systemGray3), label: "Other", value: Self.size(sizes.other))])
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Loading

    private func load() {
        var c = Counts()
        c.prayers = (try? context.fetchCount(FetchDescriptor<PrayerModel>())) ?? 0
        c.marked = (try? context.fetchCount(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted }))) ?? 0
        var first = FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted }, sortBy: [SortDescriptor(\.startTime)])
        first.fetchLimit = 1
        c.firstMarked = (try? context.fetch(first))?.first?.startTime
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>())) ?? []
        c.sessions = sessions.count
        c.zikrSeconds = sessions.reduce(0) { $0 + $1.secondsPassed }
        let azkar = (try? context.fetch(FetchDescriptor<MantraModel>())) ?? []
        c.azkar = azkar.filter { !$0.isBuiltIn }.count
        c.goals = (try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0
        c.photos = DataExport.photoCount()
        c.donations = SadaqahLog.shared.donations.count
        c.excused = Excused.ranges.count
        counts = c
        Task.detached(priority: .utility) {
            let s = DataExport.measure()
            await MainActor.run { sizes = s }
        }
    }

    private func export() {
        exporting = true
        let media = withMedia
        Task {
            // The spreadsheets from the store here (SwiftData's objects stay on the main actor), the files and the zip
            // off it.
            let sheets = DataExport.sheets(context)
            let mediaFiles = media ? DataExport.azkarMedia(context) : []
            let url = await Task.detached(priority: .userInitiated) {
                try? DataExport.zip(sheets: sheets, azkarMedia: mediaFiles, photos: media)
            }.value
            exporting = false
            if let url { exported = url } else { failed = true }
        }
    }
}

/// What Your Data reads and writes: sizes, counts and the export (.zip of CSVs, plus photos and memos if asked).
enum DataExport {
    static func photoCount() -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: PrayerPhotos.directory.path)) ?? []
        return names.filter { $0.contains("-back.") }.count
    }

    /// The store (with its external files — azkar photos and memos), prayer photos, everything else shukr keeps.
    static func measure() -> YourDataPage.Sizes {
        var s = YourDataPage.Sizes()
        let fm = FileManager.default
        let store = SharedStore.url
        let dir = store.deletingLastPathComponent()
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(store.lastPathComponent) || name.hasPrefix(".shukr_SUPPORT") {
            s.records += size(of: dir.appending(path: name))
        }
        s.photos = size(of: PrayerPhotos.directory)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        s.other = max(size(of: support) - s.photos, 0)
        s.known = true
        return s
    }

    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = walker?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: The spreadsheets

    @MainActor static func sheets(_ context: ModelContext) -> [String: String] {
        var out: [String: String] = [:]
        let prayers = (try? context.fetch(FetchDescriptor<PrayerModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        out["prayers.csv"] = table(["Prayer day", "Prayer", "Starts", "Ends", "Prayed", "Marked at", "Score", "Grade",
                                    "Masjid", "Latitude", "Longitude"], prayers.map { p in
            [p.dayKey, p.displayName, stamp(p.startTime), stamp(p.endTime), p.isCompleted ? "yes" : "no",
             p.timeAtComplete.map(stamp) ?? "", p.numberScore.map { String(Int($0.rounded())) } ?? "", p.gradeWord ?? "",
             p.mosqueName ?? "", p.latPrayedAt.map { String(format: "%.5f", $0) } ?? "",
             p.longPrayedAt.map { String(format: "%.5f", $0) } ?? ""]
        })

        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(sortBy: [SortDescriptor(\.startTime)]))) ?? []
        out["zikr-sessions.csv"] = table(["Started", "Zikr", "Goal", "Count", "Seconds", "Kind", "Target", "Seconds per count",
                                          "Ended asleep"], sessions.map { s in
            let kind = s.sessionMode == 2 ? "count" : s.sessionMode == 1 ? "time" : "freestyle"
            let target = s.sessionMode == 2 ? String(s.targetCount) : s.sessionMode == 1 ? "\(s.targetMin) min" : ""
            return [stamp(s.startTime), s.mantra?.name ?? s.title, s.task?.title ?? "", String(s.totalCount),
                    String(Int(s.secondsPassed.rounded())), kind, target,
                    s.totalCount > 0 ? String(format: "%.2f", s.secondsPassed / Double(s.totalCount)) : "",
                    s.endedAsleep ? "yes" : ""]
        })

        let azkar = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).sorted { $0.createdAt < $1.createdAt }
        out["azkar.csv"] = table(["Name", "Full text", "Notes", "Built in", "Added", "Counted", "Sessions", "Photo", "Voice memo"],
                                 azkar.map { z in
            [z.name, z.fullText, z.notes, z.isBuiltIn ? "yes" : "", stamp(z.createdAt), String(z.totalCount),
             String(z.sessions.count), z.imageData == nil ? "" : "yes", z.audioData == nil ? "" : "yes"]
        })

        let goals = ((try? context.fetch(FetchDescriptor<TaskModel>())) ?? []).sorted { $0.sortOrder < $1.sortOrder }
        out["daily-goals.csv"] = table(["Goal", "Zikr", "Kind", "Each day", "Paused", "Reminder"], goals.map { t in
            [t.title, t.displayName, t.isCountMode ? "count" : "minutes", String(t.goal),
             t.pausedAt.map(stamp) ?? "", t.reminderKind == nil ? "" : "on"]
        })

        if !SadaqahLog.shared.donations.isEmpty { out["donations.csv"] = SadaqahLog.shared.csv() }
        let ranges = Excused.ranges
        if !ranges.isEmpty {
            out["excused-mode.csv"] = table(["Started", "Estimated end", "Ended"], ranges.map {
                [stamp($0.start), stamp($0.expectedEnd), $0.end.map(stamp) ?? "still on"]
            })
        }
        out["README.txt"] = """
        Your shukr data, \(Date().formatted(date: .long, time: .shortened)).

        prayers.csv: every prayer shukr has a record of, prayed or not, with its score.
        zikr-sessions.csv: every zikr session.
        azkar.csv and daily-goals.csv: your azkar and your daily goals.
        donations.csv and excused-mode.csv: only if you've used them.
        photos/ and azkar-media/: your prayer photos (with their notes) and azkar photos and voice memos, if you chose to include them.

        Times are in your iPhone's time zone. Open the .csv files in Numbers, Excel or Google Sheets.
        """
        return out
    }

    /// Azkar photos and voice memos (kept in the store), as files named after the zikr.
    @MainActor static func azkarMedia(_ context: ModelContext) -> [(name: String, data: Data)] {
        var files: [(String, Data)] = []
        var used = Set<String>()
        for z in (try? context.fetch(FetchDescriptor<MantraModel>())) ?? [] where z.imageData != nil || z.audioData != nil {
            var base = safe(z.name)
            var n = 2
            while used.contains(base) { base = safe(z.name) + " \(n)"; n += 1 }
            used.insert(base)
            if let image = z.imageData { files.append(("\(base) photo.jpg", image)) }
            if let audio = z.audioData { files.append(("\(base) memo.m4a", audio)) }
        }
        return files
    }

    /// Writes the folder and zips it (the system's own zip: a folder read "for uploading"). Off the main thread.
    static func zip(sheets: [String: String], azkarMedia: [(name: String, data: Data)], photos: Bool) throws -> URL {
        let fm = FileManager.default
        let day = Date().formatted(.iso8601.year().month().day())
        let work = fm.temporaryDirectory.appending(path: "YourData", directoryHint: .isDirectory)
        try? fm.removeItem(at: work)
        let folder = work.appending(path: "shukr data \(day)", directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in sheets {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        if !azkarMedia.isEmpty {
            let dir = folder.appending(path: "azkar-media", directoryHint: .isDirectory)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for file in azkarMedia { try file.data.write(to: dir.appending(path: file.name)) }
        }
        if photos, photoCount() > 0 {
            try fm.copyItem(at: PrayerPhotos.directory, to: folder.appending(path: "photos", directoryHint: .isDirectory))
        }
        let out = work.appending(path: "shukr data \(day).zip")
        var coordinated: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinated) { zipped in
            do { try fm.copyItem(at: zipped, to: out) } catch { failure = error }
        }
        if let coordinated { throw coordinated }
        if let failure { throw failure }
        try? fm.removeItem(at: folder)
        return out
    }

    // MARK: Cells

    private static func table(_ head: [String], _ rows: [[String]]) -> String {
        ([head] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\n")
    }
    private static func cell(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
    private static func stamp(_ d: Date) -> String { stampFormat.string(from: d) }
    private static func safe(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Zikr" : String(cleaned.prefix(60))
    }
}

#Preview {
    NavigationStack { YourDataPage() }
}
