import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Settings → Your Data (owner, 2026-10-14): a plain "export your data" page, as any app has one ("whatever someone
// would expect to see in a page like this in any other app"): that it's private and on this iPhone, what to export (each
// kind with its size, all chosen to start with), one Export, then Restore from a copy, the backup and privacy cards.
// Top right, in the bar's Liquid Glass, a cloud (`link.icloud`, the default color) for "Is it backed up?".
//
// The facts it states (checked 2026-10-14): no network code in shukr (no account, no server, no analytics); Apple Maps is
// asked for mosques and place names; nothing is excluded from the iPhone's backup and nothing syncs; prayer photos live
// in Application Support, not the Photos library. iOS doesn't tell an app whether iCloud Backup is on or when it last ran
// (decision your-data-icloud C: say where to check + when you last made a copy). shukr's own copy in the user's iCloud
// Drive (icloud-copy-go A, `ICloudCopy`) is the one backup it can see: its section lists each copy and iCloud's state.

struct YourDataPage: View {
    @Environment(\.modelContext) private var context
    @State private var counts = Counts()
    @State private var sizes = Sizes()
    @State private var info: Info?
    @State private var chosen: Set<DataKind> = Set(DataKind.allCases)
    @State private var making = false
    @State private var made: URL?
    @State private var failed = false
    @State private var picking = false
    @State private var restore: BackupSource?
    @State private var notACopy = false
    @State private var about: DataKind?
    @State private var showBackups = false
    @AppStorage(DataExport.lastExportKey) private var lastExport: Double = 0
    @AppStorage(ICloudCopy.enabledKey) private var iCloudOn = false
    @State private var cloud = ICloudCopy.shared
    enum Info { case privacy, backup }

    struct Counts {
        var marked = 0, sessions = 0, azkar = 0, goals = 0, photos = 0, names = 0, donations = 0, excused = 0
        var firstMarked: Date?
    }
    /// What each kind takes. Prayers, zikr sessions and azkar share one store file, so the file is split between them
    /// by how much each holds (their records' size in the copy's JSON); azkar photos and voice memos are files of their
    /// own and count to azkar exactly; donations, Excused Mode and settings are their own files / entries.
    struct Sizes {
        var prayers: Int64 = 0, sessions: Int64 = 0, azkar: Int64 = 0, photos: Int64 = 0
        var names: Int64 = 0, donations: Int64 = 0, excused: Int64 = 0, settings: Int64 = 0, other: Int64 = 0
        var known = false
        func of(_ kind: DataKind) -> Int64 {
            switch kind {
            case .prayers: prayers
            case .zikr: sessions
            case .azkar: azkar
            case .photos: photos
            case .names: names
            case .donations: donations
            case .excused: excused
            case .settings: settings
            }
        }
    }

    /// The 99 Names and Excused Mode only once used; donations always (owner: people export them for their records).
    private var kinds: [DataKind] {
        DataKind.allCases.filter { ($0 != .names || counts.names > 0) && ($0 != .excused || counts.excused > 0) }
    }
    private var picked: [DataKind] { kinds.filter(chosen.contains) }

    var body: some View {
        List {
            Section {
                hero
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                ForEach(kinds, id: \.self) { pickRow($0) }
            } header: {
                HStack {
                    Text("What to export")
                    Spacer()
                    // Select All / Deselect All, top right of the list (owner).
                    Button(picked.count == kinds.count ? "Deselect All" : "Select All") {
                        if picked.count == kinds.count { chosen.subtract(kinds) } else { chosen.formUnion(kinds) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.sage)
                    .textCase(nil)
                }
            } footer: {
                // Export right under the list it exports, as a clear outlined button (owner: no gap, its own section
                // left one), the .zip line as its caption.
                VStack(spacing: 10) {
                    Button(action: export) {
                        HStack(spacing: 8) {
                            if making { ProgressView().controlSize(.small) }
                            Text(making ? "Making your copy…" : exportTitle)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                        }
                        .foregroundStyle(picked.isEmpty ? Color(.tertiaryLabel) : Color.sage)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(Capsule().strokeBorder(picked.isEmpty ? Color(.tertiaryLabel) : Color.sage, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(picked.isEmpty || making)
                    .padding(.horizontal, -4)
                    Text("A .zip with a spreadsheet for each, your photos and voice memos, and a file shukr can restore from.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 10)
                .textCase(nil)
            }
            iCloudSection
            Section {
                // The iCloud backups are hidden from Files, so Restore lists them here; "Choose a file…" for an Export.
                Button { showBackups = true } label: {
                    Label("Restore from a copy", systemImage: "arrow.counterclockwise").foregroundStyle(Color(.label))
                }
                ReminderWhyLink(symbol: "lock", title: "What stays private") { info = .privacy }
            }
        }
        .reminderPageTitle("Your Data")
        // Top right: the bar's own button, so iOS 26 draws it in Liquid Glass; the default color (owner).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The backup's state at a glance; its card says it in words (owner: one place for it, not two).
                // Orange when it needs attention, as Settings' "Check backup" (owner); no badge on top — the
                // exclamation cloud already says it.
                Button { info = .backup } label: {
                    Image(systemName: backup.symbol)
                        .foregroundStyle(backup.isProblem ? Color.orange : Color.primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                    .accessibilityLabel("iCloud Backup: " + backup.word)
            }
        }
        .task {
            load()
            cloud.measure(context)
            await cloud.refresh()
            #if DEBUG
            // `-demoRestoreFrom <path>`: the restore sheet for a copy at that path (the simulator's Files picker is slow).
            // `-demoDataKind <kind>` opens that kind's ⓘ sheet.
            if let k = UserDefaults.standard.string(forKey: "demoDataKind").flatMap(DataKind.init(rawValue:)) {
                try? await Task.sleep(for: .milliseconds(600))
                about = k
            }
            // `-demoBackupState <state>` puts the page in that state; with `-demoBackupCard YES` its card opens too.
            if UserDefaults.standard.bool(forKey: "demoBackupCard") {
                try? await Task.sleep(for: .milliseconds(600))
                info = .backup
            }
            if let path = UserDefaults.standard.string(forKey: "demoRestoreFrom") {
                restore = try? BackupSource.open(URL(fileURLWithPath: path))
            }
            #endif
        }
        // While a copy is on its way up, iCloud's state is read again every few seconds.
        .task(id: cloud.copies.contains { $0.upload == .uploading || $0.upload == .waiting }) {
            guard cloud.copies.contains(where: { $0.upload == .uploading || $0.upload == .waiting }) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await cloud.refresh()
            }
        }
        .onChange(of: iCloudOn) { _, on in
            if on { Task { await cloud.make(context, trigger: "turned on") } }
        }
        .sheet(isPresented: Binding(get: { made != nil }, set: { if !$0 { made = nil } })) {
            if let made {
                FeedbackShareSheet(items: [made]) { completed, _ in
                    if completed { lastExport = Date().timeIntervalSince1970 }
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
        .sheet(item: $about) { DataKindSheet(kind: $0) }
        .sheet(isPresented: $showBackups) {
            BackupListSheet(pick: { source in
                showBackups = false
                Task { try? await Task.sleep(for: .milliseconds(450)); restore = source }   // after this sheet has gone
            }, chooseFile: {
                showBackups = false
                Task { try? await Task.sleep(for: .milliseconds(450)); picking = true }
            })
        }
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
            Text("Pick the .zip that Export made (or the folder Files unzipped it into).")
        }
        .infoModal(isPresented: Binding(get: { info == .privacy }, set: { if !$0 { info = nil } }),
                   title: "What stays private", symbol: "lock") {
            ReminderExplainer(head: "Everything you do in shukr stays on this iPhone, and in your iCloud backup if you turn it on.", points: [
                .init(big: "No account, no server", small: "shukr has nowhere to send your data. Your prayers, zikr, photos and notes are never sent to us or anyone else.", symbol: "lock.shield", warn: false),
                .init(big: "Your location", small: "Used on your phone for prayer times, the qibla and where you prayed. Looking for mosques or a place's name asks Apple Maps, as the Maps app does.", symbol: "location", warn: false),
                .init(big: "Your photos", small: "Prayer photos stay inside shukr, not in your Photos library. They leave this iPhone only in a copy you make, or in your iCloud backup if you turn it on.", symbol: "photo.on.rectangle", warn: false),
                .init(big: "Only when you ask", small: "A copy is made when you tap Export, and goes only where you send it. iCloud Backup keeps one in your iCloud each day, hidden from Files: only shukr reads it.", symbol: "square.and.arrow.up", warn: false),
            ])
        }
        .infoModal(isPresented: Binding(get: { info == .backup }, set: { if !$0 { info = nil } }),
                   title: "iCloud Backup", symbol: backup.symbol) {
            // Restore: the card closes first, then Files opens on the page.
            BackupCard(context: context, restore: { info = nil; showBackups = true })
        }
    }

    /// The page's one focal thing: a ring holding the state — sage all round, a lock inside — over a light title and one
    /// grey line.
    private var hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 12)
                Circle().stroke(Color.sage.opacity(0.85), lineWidth: 2.5)
                Image(systemName: "lock")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(Color.sage)
            }
            .frame(width: 112, height: 112)
            .padding(.top, 8)
            Text("Your data stays with you")
                .font(.system(size: 28, weight: .light, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
            Text(iCloudOn && cloud.availability == .available
                 ? "Private: on this iPhone, and backed up daily to your iCloud, where only shukr reads it. No account and no server: nothing you do in shukr is sent to us or anyone."
                 : "Private, and only on this iPhone. No account and no server: nothing you do in shukr is sent to us or anyone.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    /// A kind to include: the check on the left (owner), what it is and its size, and an ⓘ that says what's in it.
    private func pickRow(_ kind: DataKind) -> some View {
        let on = chosen.contains(kind)
        return HStack(spacing: 12) {
            Button {
                if on { chosen.remove(kind) } else { chosen.insert(kind) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(on ? Color.sage : Color(.tertiaryLabel))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).foregroundStyle(Color(.label))
                        Text(line(kind)).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                    }
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
            Button { about = kind } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Color.sage)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About " + kind.title)
        }
    }

    /// What's in a kind, its size first once measured.
    private func line(_ kind: DataKind) -> String {
        func s(_ n: Int, _ one: String, _ many: String) -> String { "\(n.formatted()) \(n == 1 ? one : many)" }
        let what: String = switch kind {
        case .prayers: counts.marked == 0 ? "None marked yet"
            : s(counts.marked, "marked", "marked") + (counts.firstMarked.map { " since " + $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "")
        case .zikr: counts.sessions == 0 ? "None yet" : s(counts.sessions, "session", "sessions")
        case .azkar: s(counts.azkar, "of yours", "of yours") + " · " + s(counts.goals, "task", "tasks") + " · media"
        case .photos: counts.photos == 0 ? "None yet" : s(counts.photos, "photo", "photos") + " and notes"
        case .names: "\(counts.names) of 99"
        case .donations: counts.donations == 0 ? "None logged yet" : s(counts.donations, "donation", "donations") + " from Give to Causes"
        case .excused: s(counts.excused, "time", "times")
        case .settings: "Location, reminders, masajid"
        }
        // Nothing there yet: no size to give.
        return sizes.known && !what.hasPrefix("None") ? Self.size(sizes.of(kind)) + " · " + what : what
    }

    // MARK: iCloud backup

    private var backup: BackupState { BackupState.now(on: iCloudOn, cloud) }

    private func backUpNow() { Task { await cloud.make(context, trigger: "back up now") } }

    /// The switch, the latest backup and Back Up Now (owner: one line for the latest, not a list of every one).
    private var iCloudSection: some View {
        Section {
            // No clouds in this section (owner: four on one page): the top right's cloud is the state.
            Toggle("Back up to iCloud", isOn: $iCloudOn)
            .tint(.sage)
            .disabled(cloud.availability == .off && !iCloudOn && !Self.demoState)
            if showsBackupRow {
                lastBackupRow
            }
        } header: {
            Text("iCloud Backup")
        } footer: {
            Text(iCloudLine)
        }
    }

    /// The row shows while backups can run (on, iCloud Drive there); DEBUG `-demoBackupState` shows it for its state.
    /// DEBUG `-demoBackupState`: the switch works in the simulator (no iCloud there) so its state can be tried by tapping.
    private static var demoState: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "demoBackupState") != nil
        #else
        false
        #endif
    }

    private var showsBackupRow: Bool {
        switch backup {
        case .off, .noICloud: false
        default: true
        }
    }

    /// The backup the row talks about: the state's own, else the newest (a failed try keeps the last good one).
    private var rowCopy: ICloudCopy.Copy? {
        switch backup {
        case .backedUp(let c), .stale(let c): return c
        default:
            #if DEBUG
            if let demo = UserDefaults.standard.string(forKey: "demoBackupState"), demo != "none" {
                return ICloudCopy.Copy(url: URL(fileURLWithPath: "/demo.zip"), made: .now.addingTimeInterval(-26 * 3600), bytes: 2_787_884, upload: .inICloud)
            }
            #endif
            return cloud.copies.first
        }
    }

    /// One row (owner: not two under the switch): the last backup and the state's word under it, Back Up Now as a round
    /// outlined ↻ (a spinner while it runs). No Label on the right (a list lines its separators up with a row's first
    /// Label: 'In iCloud' there cut the line short); no clouds here — the top right's is the state. Everything here reads
    /// `backup`, as the top right and the card do, so they never disagree (owner: a green check under an orange cloud).
    private var lastBackupRow: some View {
        let (word, tint): (String?, Color) = switch backup {
        case .backedUp: ("In iCloud", .sage)
        case .backingUp: ("Uploading", Color(.secondaryLabel))
        case .stale: ("Out of date", .orange)
        case .failed: ("Last try didn't finish", .orange)
        case .emptier: ("Paused", .orange)
        case .none, .off, .noICloud: (nil, Color(.secondaryLabel))
        }
        let c = rowCopy
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(c == nil ? "No backup yet" : "Last backup").foregroundStyle(Color(.label))
                if let c {
                    (Text(Self.when(c.made) + " · " + Self.size(c.bytes) + (word == nil ? "" : " · ")).foregroundStyle(Color(.secondaryLabel))
                     + Text(word ?? "").foregroundStyle(tint))
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 8)
            // Paused (this iPhone holds much less than the backup): the card explains and offers Restore instead.
            Button(action: { if case .emptier = backup { info = .backup } else { backUpNow() } }) {
                ZStack {
                    Circle().strokeBorder(Color.sage, lineWidth: 1.2)
                    if cloud.working {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sage)
                    }
                }
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(cloud.working)
            .accessibilityLabel(cloud.working ? "Backing up" : "Back Up Now")
        }
        .padding(.vertical, 2)
    }

    private var iCloudLine: String {
        switch backup {
        case .off: return "Backs up everything to your iCloud once a day, hidden from Files. Only shukr reads it."
        case .noICloud: return "iCloud Drive is off on this iPhone. Turn it on in Settings → your name → iCloud → iCloud Drive."
        default: return "Once a day, when you open shukr, everything is backed up to your iCloud, hidden from Files: only shukr reads it. The newest \(ICloudCopy.keep) are kept, and your fullest is never deleted. For files you can open, use Export."
        }
    }

    /// "Today, 3:12 PM" / "Yesterday, 9:40 PM" / "Oct 12, 9:40 PM".
    static func when(_ d: Date) -> String {
        let time = d.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(d) { return "Today, " + time }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday, " + time }
        return d.formatted(.dateTime.month(.abbreviated).day()) + ", " + time
    }

    private var exportTitle: String {
        guard sizes.known, !picked.isEmpty else { return "Export" }
        return "Export · about " + Self.size(picked.reduce(0) { $0 + sizes.of($1) })
    }

    private func export() {
        making = true
        let include = Set(picked)
        Task {
            let url = await DataExport.makeCopy(context, include: include)
            making = false
            if let url { made = url } else { failed = true }
        }
    }

    static func size(_ bytes: Int64) -> String {
        bytes < 1000 ? "under 1 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: Loading

    private func load() {
        var c = Counts()
        // Prayers whose time has come (a test mark ahead of time isn't one).
        let now = Date()
        c.marked = (try? context.fetchCount(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted && $0.startTime <= now }))) ?? 0
        var first = FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted }, sortBy: [SortDescriptor(\.startTime)])
        first.fetchLimit = 1
        c.firstMarked = (try? context.fetch(first))?.first?.startTime
        c.sessions = (try? context.fetchCount(FetchDescriptor<SessionDataModel>())) ?? 0
        c.azkar = ((try? context.fetch(FetchDescriptor<MantraModel>())) ?? []).filter { !$0.isBuiltIn }.count
        c.goals = (try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0
        c.photos = DataExport.photoCount()
        c.names = KnownNames.decode(UserDefaults.standard.string(forKey: KnownNames.key) ?? "").count
        c.donations = SadaqahLog.shared.donations.count
        c.excused = Excused.ranges.count
        counts = c
        let weights = DataExport.weights(context)
        Task.detached(priority: .utility) {
            let s = DataExport.measure(weights)
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .light)).foregroundStyle(.secondary).frame(width: 24)
            Text(text).font(.system(.subheadline, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)   // wraps, never "…" (a sheet's first, smaller size cut it)
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

/// A kind's ⓘ: what's in it, where it comes from, where it lands in the copy — a sheet as tall as its words.
private struct DataKindSheet: View {
    let kind: DataKind
    @State private var height: CGFloat = 340
    var body: some View {
        VStack(spacing: 0) {
            SheetHead(symbol: kind.symbol, title: kind.title, line: kind.about)
            VStack(alignment: .leading, spacing: 2) {
                SheetLine(symbol: "hand.tap", text: kind.source)
                SheetLine(symbol: "doc.text", text: "In your copy: " + kind.files)
            }
            .padding(.horizontal, 32).padding(.top, 18).padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)   // measured at its own height, not the sheet's current one
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(GlassSheet(height: height))
    }
}

/// Restore from a copy: the iCloud backups (hidden from Files, so listed here), newest first, the fullest marked; a tap
/// brings it down if needed and opens the restore sheet. "Choose a file…" for an Export kept elsewhere.
private struct BackupListSheet: View {
    let pick: (BackupSource) -> Void
    let chooseFile: () -> Void
    @State private var copies: [ICloudCopy.Copy]?
    @State private var opening: URL?
    @State private var failed = false
    @State private var height: CGFloat = 380

    private var fullest: URL? {
        copies?.filter { $0.counts != nil }.max { $0.counts!.score < $1.counts!.score }?.url
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHead(symbol: "arrow.counterclockwise", title: "Restore from a backup",
                      line: "Only what's missing is added. Nothing on this iPhone is changed or removed.")
            VStack(spacing: 8) {
                if let copies {
                    if copies.isEmpty {
                        Text("No iCloud backups yet.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(copies.prefix(6)) { row($0) }
                    }
                } else {
                    ProgressView().padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 24).padding(.top, 18)
            Button("Choose a file…", action: chooseFile)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.sage)
                .padding(.top, 16).padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(GlassSheet(height: height))
        .task {
            #if DEBUG
            // `-demoBackupList`: stand-in backups (the simulator has no iCloud).
            if UserDefaults.standard.bool(forKey: "demoBackupList") {
                let u = { (n: String) in URL(fileURLWithPath: "/" + n) }
                copies = [ICloudCopy.Copy(url: u("a"), made: .now.addingTimeInterval(-3600), bytes: 2_900_000, upload: .inICloud, counts: .init(prayers: 2215, sessions: 142, photos: 83)),
                          ICloudCopy.Copy(url: u("b"), made: .now.addingTimeInterval(-86400 - 3600), bytes: 2_880_000, upload: .inICloud, counts: .init(prayers: 2210, sessions: 141, photos: 82)),
                          ICloudCopy.Copy(url: u("c"), made: .now.addingTimeInterval(-2 * 86400), bytes: 2_787_884, upload: .inICloud)]
                return
            }
            #endif
            copies = await ICloudCopy.backupsForRestore()
        }
        .alert("Couldn't open that backup", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check that you're online, then try again.")
        }
    }

    private func row(_ c: ICloudCopy.Copy) -> some View {
        Button { open(c) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(YourDataPage.when(c.made))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color(.label))
                    Text(c.counts.map { "\($0.prayers.formatted()) prayers · \($0.sessions.formatted()) sessions · \($0.photos.formatted()) photos" }
                         ?? YourDataPage.size(c.bytes))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 6)
                if c.url == fullest {
                    Text("Fullest")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.sage)
                }
                if opening == c.url {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(opening != nil)
    }

    private func open(_ c: ICloudCopy.Copy) {
        opening = c.url
        Task {
            do {
                let url = try await ICloudCopy.localCopy(of: c)
                let source = try BackupSource.open(url)
                opening = nil
                pick(source)
            } catch {
                opening = nil
                failed = true
            }
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
    @State private var restoring = false

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
                PrimaryButton(title: restoring ? "Restoring…" : "Restore", enabled: planned && !restoring) {
                    restoring = true
                    Task { @MainActor in
                        // A frame for "Restoring…" first: thousands of rows take a moment.
                        try? await Task.sleep(for: .milliseconds(80))
                        added = DataRestore.apply(source, context)
                        restoring = false
                        done()
                    }
                }
                SecondaryButton(title: "Not now") { dismiss() }
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // As tall as its lines need (a full copy lists ten).
        .modifier(GlassSheet(height: min(360 + CGFloat(max(lines(added ?? plan).count, 1)) * 31, 720)))
        .task {
            plan = DataRestore.plan(source, context)
            planned = true
        }
    }

    private func lines(_ p: RestorePlan) -> [(String, String)] {
        func n(_ count: Int, _ one: String, _ many: String) -> String { "\(count.formatted()) \(count == 1 ? one : many)" }
        var out: [(String, String)] = []
        if p.prayers > 0 { out.append(("checkmark.circle", n(p.prayers, "prayer", "prayers"))) }
        if p.prayersMarked > 0 { out.append(("checkmark.circle.fill", n(p.prayersMarked, "mark", "marks") + " for prayers left unmarked here")) }
        if p.sessions > 0 { out.append(("circle.hexagonpath", n(p.sessions, "zikr session", "zikr sessions"))) }
        if p.azkar > 0 { out.append(("books.vertical", n(p.azkar, "zikr of yours", "azkar of yours"))) }
        if p.goals > 0 { out.append(("target", n(p.goals, "task", "tasks"))) }
        if p.photos > 0 { out.append(("camera", n(p.photos, "prayer photo", "prayer photos"))) }
        if p.donations > 0 { out.append(("gift", n(p.donations, "donation", "donations"))) }
        if p.excused > 0 { out.append(("pause.circle", n(p.excused, "Excused Mode stretch", "Excused Mode stretches"))) }
        if p.names > 0 { out.append(("character.book.closed", n(p.names, "of the 99 Names learned", "of the 99 Names learned"))) }
        if p.photoFavorites > 0 { out.append(("heart", n(p.photoFavorites, "hearted photo", "hearted photos"))) }
        if p.masajid > 0 { out.append(("star", n(p.masajid, "starred masjid", "starred masajid"))) }
        if p.hidden > 0 { out.append(("eye.slash", n(p.hidden, "hidden masjid", "hidden masajid"))) }
        if p.bests > 0 { out.append(("flame", n(p.bests, "best streak", "best streaks"))) }
        return out
    }
}

// MARK: - Export

/// What Your Data reads and writes: sizes, counts and the copy (.zip of CSVs + shukr-backup.json, photos and memos if asked).
enum DataExport {
    static let lastExportKey = "yourData.lastExport"

    /// The copy of what's chosen: the spreadsheets and the backup from the store here (SwiftData's objects stay on the
    /// main actor), the files and the zip off it. In tmp/YourData. Zikr sessions keep their azkar's records in the backup
    /// (so a restore links them), not their media.
    /// `work`: its own temp folder (the backup uses "YourDataBackup"), so an Export and a backup at once can't clear
    /// each other's files.
    @MainActor static func makeCopy(_ context: ModelContext, include: Set<DataKind> = Set(DataKind.allCases), work: String = "YourData") async -> URL? {
        var all = sheets(context)
        all["settings.csv"] = DataSettings.csv()
        let names = Set(include.flatMap(\.sheets) + ["README.txt"])
        let sheets = all.filter { names.contains($0.key) }
        var (b, files) = backup(context, media: include.contains(.azkar))
        if !include.contains(.prayers) { b.prayers = []; b.dayScores = [] }
        if !include.contains(.zikr) { b.sessions = [] }
        if !include.contains(.azkar) { b.goals = []; if !include.contains(.zikr) { b.azkar = [] } }
        if !include.contains(.donations) { b.donations = [] }
        if !include.contains(.excused) { b.excused = [] }
        if !include.contains(.azkar) { files = [] }
        if !include.contains(.prayers) { b.bests = nil }
        if !include.contains(.photos) { b.photoFavorites = nil }
        if !include.contains(.names) { b.namesKnown = nil }
        if !include.contains(.settings) { b.favoriteMosques = nil; b.hiddenMosques = nil; b.settings = nil }
        let json = (try? ShukrBackup.encoder.encode(b)) ?? Data()
        let photos = include.contains(.photos)
        return await Task.detached(priority: .userInitiated) {
            try? zip(sheets: sheets, json: json, azkarMedia: files, photos: photos, work: work)
        }.value
    }

    /// Photos by prayer (a prayer saved as both .heic and .jpg is one photo), as the photos page and Memories count them.
    static func photoCount() -> Int { PrayerPhotos.all().count }

    /// How much of the store is prayers and how much zikr: the size of each one's records written out as the copy writes
    /// them (main actor: SwiftData's objects).
    @MainActor static func weights(_ context: ModelContext) -> (prayers: Double, sessions: Double, azkar: Double) {
        let (b, _) = backup(context, media: false)
        let e = JSONEncoder()
        func bytes<T: Encodable>(_ v: T) -> Double { Double((try? e.encode(v))?.count ?? 0) }
        return (bytes(b.prayers) + bytes(b.dayScores), bytes(b.sessions), bytes(b.azkar) + bytes(b.goals))
    }

    /// The store split by `weights` (its external files — azkar photos and memos — to azkar), prayer photos, the
    /// donations log, Excused Mode's record, the settings files, everything else shukr keeps.
    static func measure(_ weights: (prayers: Double, sessions: Double, azkar: Double) = (1, 1, 1)) -> YourDataPage.Sizes {
        var s = YourDataPage.Sizes()
        let fm = FileManager.default
        let store = SharedStore.url
        let dir = store.deletingLastPathComponent()
        var file: Int64 = 0, media: Int64 = 0
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            if name.hasPrefix(store.lastPathComponent) { file += size(of: dir.appending(path: name)) }
            else if name.hasPrefix(".shukr_SUPPORT") { media += size(of: dir.appending(path: name)) }
        }
        let all = max(weights.prayers + weights.sessions + weights.azkar, 1)
        s.prayers = Int64(Double(file) * weights.prayers / all)
        s.sessions = Int64(Double(file) * weights.sessions / all)
        s.azkar = file - s.prayers - s.sessions + media
        s.photos = size(of: PrayerPhotos.directory)
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        s.donations = size(of: support.appending(path: "Sadaqah"))
        s.other = max(size(of: support) - s.photos - s.donations, 0)
        // Settings: the app's and the app group's preferences (Excused Mode's record lives in the group's, apart).
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        var prefs = exactSize(library.appending(path: "Preferences/com.betternorms.shukr.plist"))
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup) {
            prefs += exactSize(group.appending(path: "Library/Preferences/\(SharedStore.appGroup).plist"))
        }
        s.excused = Int64(UserDefaults(suiteName: SharedStore.appGroup)?.data(forKey: Excused.key)?.count ?? 0)
        s.names = Int64(UserDefaults.standard.string(forKey: KnownNames.key)?.utf8.count ?? 0)
        s.settings = max(prefs - s.excused - s.names, 0)
        s.known = true
        return s
    }

    /// A small file's own size (allocated sizes round a 2 KB file up to 4 KB).
    private static func exactSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
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
             p.timeAtComplete.map(stamp) ?? "", p.numberScore.map { String(Int(($0 * 100).rounded())) } ?? "", p.gradeWord ?? "",
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
        out["tasks.csv"] = table(["Task", "Zikr", "Kind", "Each day", "Paused", "Reminder"], goals.map { t in
            [t.title, t.displayName, t.isCountMode ? "count" : "minutes", String(t.goal),
             t.pausedAt.map(stamp) ?? "", t.reminderKind == nil ? "" : "on"]
        })

        if !SadaqahLog.shared.donations.isEmpty { out["donations.csv"] = SadaqahLog.shared.csv() }
        let known = KnownNames.decode(UserDefaults.standard.string(forKey: KnownNames.key) ?? "")
        out["names-learned.csv"] = table(["Number", "Name", "Arabic", "Meaning"], NamesOfAllah.all.filter { known.contains($0.id) }.map {
            [String($0.id), $0.transliteration, $0.arabic, $0.meaning]
        })
        out["your-masajid.csv"] = table(["Masjid", "Latitude", "Longitude", "Starred or hidden"],
            MosqueFavorites.all.map { [$0.name, String(format: "%.5f", $0.latitude), String(format: "%.5f", $0.longitude), "starred"] }
            + (UserDefaults.standard.stringArray(forKey: MosqueHiding.key) ?? []).map { id in
                let p = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                return [p.first ?? id, p.count > 1 ? p[1] : "", p.count > 2 ? p[2] : "", "hidden"]
            })
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
        azkar.csv and tasks.csv: your azkar and your tasks.
        names-learned.csv: the 99 Names you've marked as learned.
        donations.csv and excused-mode.csv: when you've used them and chose them.
        settings.csv and your-masajid.csv: your settings, and the masajid you starred or hid on the map.
        photos/ and azkar-media/: your prayer photos (with their notes) and azkar photos and voice memos, when you chose them.
        shukr-backup.json: everything above for shukr itself. To bring it back, open shukr → Settings → Your Data → Restore from a copy, and pick this .zip.

        Times are in your iPhone's time zone. Open the .csv files in Numbers, Excel or Google Sheets.
        """
        return out
    }

    /// Writes the folder and zips it (the system's own zip: a folder read "for uploading"). Off the main thread.
    static func zip(sheets: [String: String], json: Data, azkarMedia: [(name: String, data: Data)], photos: Bool,
                    work workName: String = "YourData") throws -> URL {
        let fm = FileManager.default
        let day = Date().formatted(.iso8601.year().month().day())
        let work = fm.temporaryDirectory.appending(path: workName, directoryHint: .isDirectory)
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
