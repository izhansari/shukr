import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Settings → Your Data (owner, 2026-10-14): what shukr keeps, that it's private and on this iPhone only, whether it's
// backed up, a copy of it all, and a restore from one. Its own page in shukr's soft look (owner: "way too similar" to the
// "Your …" reminder pages) — Sami's design language (board/mocks/design-library): one ring holding the state in the
// middle, light type, a raised card for the figures, sage only on what you can tap, one pill and a quiet line; the ⓘ in
// the bar's Liquid Glass. The export and the restore are glass sheets in the "topped up" sheet's template.
//
// The facts it states (checked 2026-10-14): no network code in shukr (no account, no server, no analytics); Apple Maps is
// asked for mosques and place names; nothing is excluded from the iPhone's backup and nothing syncs (no CloudKit);
// prayer photos live in Application Support, not the Photos library. iOS doesn't tell an app whether iCloud Backup is on
// (decision your-data-icloud C: say where to check + when you last made a copy; shukr's own iCloud Drive copy later).

struct YourDataPage: View {
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @State private var counts = Counts()
    @State private var sizes = Sizes()
    @State private var info: Info?
    @State private var exportSheet = false
    @State private var picking = false
    @State private var restore: BackupSource?
    @State private var notACopy = false
    @State private var titleShown = false
    @AppStorage(DataExport.lastExportKey) private var lastExport: Double = 0
    enum Info { case privacy, backup }

    struct Counts {
        var marked = 0, sessions = 0, azkar = 0, goals = 0, photos = 0, donations = 0, excused = 0
        var firstMarked: Date?
        var zikrSeconds: Double = 0
    }
    struct Sizes {
        var records: Int64 = 0, photos: Int64 = 0, other: Int64 = 0
        var total: Int64 { records + photos + other }
        var known = false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                figures.padding(.top, 30)
                backupCard.padding(.top, 16)
                VStack(spacing: 0) {
                    PrimaryButton(title: "Export my data") { exportSheet = true }
                    SecondaryButton(title: "Restore from a copy") { picking = true }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 150 } action: { _, under in
            withAnimation(.easeOut(duration: 0.15)) { titleShown = under }
        }
        .navigationTitle(titleShown ? "Your Data" : "")
        .navigationBarTitleDisplayMode(.inline)
        // Top right: the bar's own button, so iOS 26 draws it in Liquid Glass.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The ⓘ as everywhere else in shukr: info.circle in the default color (owner: never sage).
                Button { info = .privacy } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("What stays private")
            }
        }
        .task {
            load()
            #if DEBUG
            // `-demoRestoreFrom <path>`: the restore sheet for a copy at that path (the simulator's Files picker is slow).
            if let path = UserDefaults.standard.string(forKey: "demoRestoreFrom") {
                restore = try? BackupSource.open(URL(fileURLWithPath: path))
            }
            #endif
        }
        .sheet(isPresented: $exportSheet) { ExportSheet(sizes: sizes) }
        .sheet(item: Binding(get: { restore.map(RestoreBox.init) }, set: { if $0 == nil { restore = nil } })) {
            RestoreSheet(source: $0.source) { load() }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.zip, .folder, .json]) { result in
            guard case .success(let url) = result else { return }
            do { restore = try BackupSource.open(url) } catch { notACopy = true }
        }
        .alert("That isn't a shukr copy", isPresented: $notACopy) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pick the .zip that Export my data made (or the folder Files unzipped it into).")
        }
        .infoModal(isPresented: Binding(get: { info == .privacy }, set: { if !$0 { info = nil } }),
                   title: "What stays private", symbol: "lock") {
            ReminderExplainer(head: "Everything you do in shukr stays on this iPhone.", points: [
                .init(big: "No account, no server", small: "shukr has nowhere to send your data. Your prayers, zikr, photos and notes are never sent to us or anyone else.", symbol: "lock.shield", warn: false),
                .init(big: "Your location", small: "Used on your phone for prayer times, the qibla and where you prayed. Looking for mosques or a place's name asks Apple Maps, as the Maps app does.", symbol: "location", warn: false),
                .init(big: "Your photos", small: "Prayer photos stay inside shukr, not in your Photos library, and they're never synced.", symbol: "photo.on.rectangle", warn: false),
                .init(big: "Only when you ask", small: "A copy is made only when you tap Export, and it goes only where you send it.", symbol: "square.and.arrow.up", warn: false),
            ])
        }
        .infoModal(isPresented: Binding(get: { info == .backup }, set: { if !$0 { info = nil } }),
                   title: "Is it backed up?", symbol: "icloud") {
            ReminderExplainer(head: "shukr is part of your iPhone's own backup. iOS doesn't let apps see whether that backup is on, so here's how to check.", points: [
                .init(big: "Check iCloud Backup", small: "Settings → your name → iCloud → iCloud Backup. When it's on, shukr is in it, photos too.", symbol: "icloud", warn: false),
                .init(big: "On a new iPhone", small: "Set it up from that backup and shukr comes back with your history, photos and goals.", symbol: "iphone", warn: false),
                .init(big: "Deleting shukr deletes it", small: "Removing the app removes its data from this iPhone too. Backups made before still have it.", symbol: "trash", warn: false, neutral: true),
                .init(big: "Your own copy", small: "Export my data makes a copy you can keep anywhere, and Restore from a copy brings it back.", symbol: "square.and.arrow.up", warn: false),
            ])
        }
    }

    // MARK: The parts

    /// The one thing in the middle (README 1–2): a soft ring holding the state — sage all round, a lock inside.
    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(theme.surface, lineWidth: 14)
                    .shadow(color: theme.shade, radius: 4, x: 3, y: 3)
                    .shadow(color: theme.light, radius: 4, x: -3, y: -3)
                Circle().stroke(Color.sage.opacity(0.75), lineWidth: 2.5)
                Image(systemName: "lock")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(Color.sage)
            }
            .frame(width: 124, height: 124)
            .padding(.top, 18)
            Text("Your data stays with you")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text("Private, and only on this iPhone. No account and no server: nothing you do in shukr is sent to us or anyone.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// What's on this iPhone, as figures (README: a summary, then quiet density), and the room it takes.
    private var figures: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ON THIS IPHONE").font(.caption.weight(.medium)).tracking(1.2).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 18) {
                GridRow {
                    figure(counts.marked, "prayers marked", counts.firstMarked.map { "since " + $0.formatted(.dateTime.month(.abbreviated).year()) })
                    figure(counts.sessions, "zikr sessions", counts.sessions > 0 ? zikrTime : nil)
                }
                GridRow {
                    figure(counts.photos, "prayer photos", sizes.known && counts.photos > 0 ? Self.size(sizes.photos) : nil)
                    figure(counts.azkar, counts.azkar == 1 ? "zikr of yours" : "azkar of yours", "\(counts.goals) daily goal\(counts.goals == 1 ? "" : "s")")
                }
            }
            if counts.donations > 0 || counts.excused > 0 {
                Text([counts.donations > 0 ? "\(counts.donations) donation\(counts.donations == 1 ? "" : "s") logged" : nil,
                      counts.excused > 0 ? "Excused Mode \(counts.excused) time\(counts.excused == 1 ? "" : "s")" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            sizeBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), radius: 8, offset: 4))
    }

    private func figure(_ n: Int, _ label: String, _ line: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(n.formatted()).font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
            Text(label).font(.subheadline)
            Text(line ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var zikrTime: String {
        let s = counts.zikrSeconds
        if s < 60 { return "under a minute" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min in all" }
        let h = Int((s / 3600).rounded())
        return "\(h.formatted()) hour\(h == 1 ? "" : "s") in all"
    }

    /// The room it takes in parts (the "Your …" pages' bar, thinner and without a key's counts).
    private var sizeBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(sizes.known ? "\(Self.size(sizes.total)) in all" : "Measuring…")
                Spacer()
                if sizes.known {
                    HStack(spacing: 10) {
                        key(Color.sage, "Records")
                        if sizes.photos > 0 { key(Color(.systemTeal), "Photos") }
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 1.5) {
                    let total = max(Double(sizes.total), 1)
                    ForEach([(sizes.records, Color.sage), (sizes.photos, Color(.systemTeal)), (sizes.other, Color(.systemGray3))],
                            id: \.1) { part in
                        if part.0 > 0 {
                            Capsule().fill(part.1).frame(width: max(geo.size.width * Double(part.0) / total - 1.5, 3))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 4)
        }
    }

    private func key(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 6, height: 6); Text(label) }
    }

    /// Backed up? What shukr can say: it's in the iPhone's backup, where to check, and when you last made a copy.
    private var backupCard: some View {
        Button { info = .backup } label: {
            HStack(spacing: 14) {
                Image(systemName: "icloud")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("In your iPhone's backup").foregroundStyle(.primary)
                    Text(exportLine).font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(NeuRaised(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), radius: 8, offset: 4))
    }

    /// When the last copy was made, and a gentle word when it's been a while (decision your-data-icloud C).
    private var exportLine: String {
        guard lastExport > 0 else { return "When iCloud Backup is on, shukr is in it. You haven't made a copy of your own yet." }
        let when = Date(timeIntervalSince1970: lastExport)
        let days = Calendar.current.dateComponents([.day], from: when, to: .now).day ?? 0
        let said = "Your last copy: " + when.formatted(.dateTime.month(.abbreviated).day().year())
        return days >= 30 ? said + ". A fresh one takes a moment." : said + "."
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Loading

    private func load() {
        var c = Counts()
        c.marked = (try? context.fetchCount(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted }))) ?? 0
        var first = FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted }, sortBy: [SortDescriptor(\.startTime)])
        first.fetchLimit = 1
        c.firstMarked = (try? context.fetch(first))?.first?.startTime
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>())) ?? []
        c.sessions = sessions.count
        c.zikrSeconds = sessions.reduce(0) { $0 + $1.secondsPassed }
        c.azkar = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).filter { !$0.isBuiltIn }.count
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
}

private struct RestoreBox: Identifiable {
    let source: BackupSource
    var id: Date { source.backup.made }
}

// MARK: - The sheets

/// The glass sheet's top (the "topped up" sheet's template): a symbol in a ring, a light title, one grey line.
private struct SheetHead: View {
    let symbol: String
    let title: String
    let line: String
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Color.sage.opacity(0.18), lineWidth: 1.2)
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Color.sage)
            }
            .frame(width: 64, height: 64)
            .padding(.top, 26)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .light))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 16)
            Text(line)
                .font(.system(.callout, design: .rounded, weight: .light))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32).padding(.top, 8)
        }
    }
}

private struct SheetLine: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .light)).foregroundStyle(.secondary).frame(width: 24)
            Text(text).font(.system(.subheadline, design: .rounded))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

private struct GlassSheet: ViewModifier {
    let height: CGFloat
    func body(content: Content) -> some View {
        let sized = content
            .fontDesign(.rounded)
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
        if #available(iOS 26.0, *) { sized } else { sized.presentationBackground(.regularMaterial) }
    }
}

/// Export my data: what goes in, photos and memos or not, then the system share sheet.
private struct ExportSheet: View {
    let sizes: YourDataPage.Sizes
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DataExport.lastExportKey) private var lastExport: Double = 0
    @State private var withMedia = true
    @State private var making = false
    @State private var made: URL?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHead(symbol: "square.and.arrow.up", title: "A copy of your data",
                      line: "A .zip you can keep anywhere, and bring back with Restore from a copy.")
            VStack(alignment: .leading, spacing: 2) {
                SheetLine(symbol: "tablecells", text: "Spreadsheets of your prayers, zikr, azkar, goals and donations")
                SheetLine(symbol: "arrow.counterclockwise", text: "Everything shukr needs to restore it")
                Toggle(isOn: $withMedia) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo").font(.system(size: 15, weight: .light)).foregroundStyle(.secondary).frame(width: 24)
                        Text("Photos and voice memos" + (sizes.known && sizes.photos > 0 ? " · \(YourDataPage.size(sizes.photos))" : ""))
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
                .tint(Color.sage)
                .padding(.vertical, 2)
            }
            .padding(.horizontal, 32).padding(.top, 18)
            Spacer(minLength: 12)
            PrimaryButton(title: making ? "Making your copy…" : "Make my copy", enabled: !making) { make() }
            SecondaryButton(title: "Not now") { dismiss() }
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassSheet(height: 470))
        .sheet(isPresented: Binding(get: { made != nil }, set: { if !$0 { made = nil } })) {
            if let made {
                FeedbackShareSheet(items: [made]) { completed, _ in
                    guard completed else { return }
                    lastExport = Date().timeIntervalSince1970
                    dismiss()
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
        }
        .alert("Couldn't make the copy", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your data is safe. Try again in a moment, or without photos if space is short.")
        }
    }

    private func make() {
        making = true
        let media = withMedia
        Task {
            // The spreadsheets and the backup from the store here (SwiftData's objects stay on the main actor), the files
            // and the zip off it.
            let url = await DataExport.makeCopy(context, media: media)
            making = false
            if let url { made = url } else { failed = true }
        }
    }
}

/// Restore from a copy: what it would add (nothing here changes), then add it.
private struct RestoreSheet: View {
    let source: BackupSource
    let done: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var plan = RestorePlan()
    @State private var added: RestorePlan?
    @State private var planned = false

    var body: some View {
        VStack(spacing: 0) {
            if let added {
                SheetHead(symbol: "checkmark", title: "Restored",
                          line: added.total == 0 ? "Nothing was missing." : "Added what was missing. Your streaks and scores are counted again.")
            } else {
                SheetHead(symbol: "arrow.counterclockwise", title: "Restore from your copy",
                          line: "Made \(source.backup.made.formatted(date: .abbreviated, time: .shortened)). Only what's missing is added; nothing on this iPhone is changed or removed.")
            }
            VStack(alignment: .leading, spacing: 2) {
                let shown = lines(added ?? plan)
                if planned && shown.isEmpty && added == nil {
                    SheetLine(symbol: "checkmark.circle", text: "This iPhone already has everything in it")
                }
                ForEach(shown, id: \.1) { SheetLine(symbol: $0.0, text: $0.1) }
            }
            .padding(.horizontal, 32).padding(.top, 16)
            Spacer(minLength: 12)
            if added != nil || (planned && plan.total == 0) {
                PrimaryButton(title: "Done") { dismiss() }
                    .padding(.bottom, 26)
            } else {
                PrimaryButton(title: "Restore", enabled: planned) {
                    added = DataRestore.apply(source, context)
                    done()
                }
                SecondaryButton(title: "Not now") { dismiss() }
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassSheet(height: 500))
        .task {
            plan = DataRestore.plan(source, context)
            planned = true
        }
    }

    private func lines(_ p: RestorePlan) -> [(String, String)] {
        func n(_ count: Int, _ one: String, _ many: String) -> String { "\(count.formatted()) \(count == 1 ? one : many)" }
        var out: [(String, String)] = []
        if p.prayers > 0 { out.append(("checkmark.circle", n(p.prayers, "prayer", "prayers"))) }
        if p.prayersMarked > 0 { out.append(("checkmark.circle.fill", n(p.prayersMarked, "prayer marked", "prayers marked") + " that weren't here")) }
        if p.sessions > 0 { out.append(("circle.hexagonpath", n(p.sessions, "zikr session", "zikr sessions"))) }
        if p.azkar > 0 { out.append(("books.vertical", n(p.azkar, "zikr of yours", "azkar of yours"))) }
        if p.goals > 0 { out.append(("target", n(p.goals, "daily goal", "daily goals"))) }
        if p.photos > 0 { out.append(("camera", n(p.photos, "prayer photo", "prayer photos"))) }
        if p.donations > 0 { out.append(("gift", n(p.donations, "donation", "donations"))) }
        if p.excused > 0 { out.append(("pause.circle", n(p.excused, "Excused Mode stretch", "Excused Mode stretches"))) }
        return out
    }
}

// MARK: - Export

/// What Your Data reads and writes: sizes, counts and the copy (.zip of CSVs + shukr-backup.json, photos and memos if asked).
enum DataExport {
    static let lastExportKey = "yourData.lastExport"

    /// The whole copy: the spreadsheets and the backup from the store here (SwiftData's objects stay on the main actor),
    /// the files and the zip off it. In tmp/YourData.
    @MainActor static func makeCopy(_ context: ModelContext, media: Bool) async -> URL? {
        let sheets = sheets(context)
        let (backup, files) = backup(context, media: media)
        let json = (try? ShukrBackup.encoder.encode(backup)) ?? Data()
        return await Task.detached(priority: .userInitiated) {
            try? zip(sheets: sheets, json: json, azkarMedia: files, photos: media)
        }.value
    }

    static func photoCount() -> Int {
        PrayerPhotos.files().filter { $0.contains("-back.") }.count
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
        shukr-backup.json: everything above for shukr itself. To bring it back, open shukr → Settings → Your Data → Restore from a copy, and pick this .zip.

        Times are in your iPhone's time zone. Open the .csv files in Numbers, Excel or Google Sheets.
        """
        return out
    }

    /// Writes the folder and zips it (the system's own zip: a folder read "for uploading"). Off the main thread.
    static func zip(sheets: [String: String], json: Data, azkarMedia: [(name: String, data: Data)], photos: Bool) throws -> URL {
        let fm = FileManager.default
        let day = Date().formatted(.iso8601.year().month().day())
        let work = fm.temporaryDirectory.appending(path: "YourData", directoryHint: .isDirectory)
        try? fm.removeItem(at: work)
        let folder = work.appending(path: "shukr data \(day)", directoryHint: .isDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in sheets {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        try json.write(to: folder.appending(path: ShukrBackup.fileName))
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
    static func safeName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Zikr" : String(cleaned.prefix(60))
    }
}

#Preview {
    NavigationStack { YourDataPage() }
}
