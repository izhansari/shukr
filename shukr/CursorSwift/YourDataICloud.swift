import Foundation
import SwiftData
import UIKit
import SwiftUI

// shukr's own copy in iCloud Drive (owner, 2026-10-14, decision icloud-copy-go A; container set up by Bradley):
// Your Data → "Copy to iCloud Drive" saves the full copy (the same .zip Export makes) to iCloud Drive → shukr once a day,
// keeps the newest `keep`, and logs every try. The page lists the copies with iCloud's own upload state, so you can see
// they're there. iOS still doesn't tell an app about the iPhone's own backup; this is shukr's copy, which we can see.
// Restore from a copy opens Files, where the shukr folder is.

@MainActor @Observable final class ICloudCopy {
    static let shared = ICloudCopy()
    nonisolated static let containerID = "iCloud.com.betternorms.shukr"
    static let enabledKey = "yourData.icloud.on"
    /// Copies kept in iCloud Drive (each one is whole, so only the newest few are worth their space).
    nonisolated static let keep = 3
    /// "Once a day": 20 h, so a copy made at 9 PM is due again the next evening.
    static let every: TimeInterval = 20 * 3600
    nonisolated private static let prefix = "shukr data "

    enum Availability: Equatable { case checking, available, off }
    enum Upload: Equatable { case inICloud, uploading, waiting, failed(String) }
    struct Copy: Identifiable, Equatable {
        let url: URL, made: Date, bytes: Int64, upload: Upload
        var id: URL { url }
    }
    struct LogLine: Codable, Equatable {
        let at: Date, ok: Bool, bytes: Int64?, why: String?, trigger: String
    }

    private(set) var availability: Availability = .checking
    private(set) var copies: [Copy] = []
    private(set) var working = false
    private(set) var log: [LogLine] = []
    private var documents: URL?

    var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }
    var lastSuccess: Date? { log.last(where: \.ok)?.at }
    var lastFailure: LogLine? { log.last.flatMap { $0.ok ? nil : $0 } }

    private init() { log = Self.readLog() }

    /// iCloud Drive's folder for shukr (`url(forUbiquityContainerIdentifier:)` can block: off the main thread), then the
    /// copies in it.
    func refresh() async {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            availability = .off; copies = []; documents = nil
            return
        }
        let docs = await Task.detached(priority: .utility) { () -> URL? in
            guard let root = FileManager.default.url(forUbiquityContainerIdentifier: ICloudCopy.containerID) else { return nil }
            let docs = root.appending(path: "Documents", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            return docs
        }.value
        documents = docs
        availability = docs == nil ? .off : .available
        guard let docs else { copies = []; return }
        copies = await Task.detached(priority: .utility) { ICloudCopy.list(docs) }.value
    }

    /// A copy if one's due: on, iCloud there, none made in the last `every`. From the app's activation, after a beat.
    func runIfDue(_ context: ModelContext, trigger: String) async {
        guard isOn, !working else { return }
        if let last = lastSuccess, Date().timeIntervalSince(last) < Self.every { return }
        await make(context, trigger: trigger)
    }

    /// Makes the full copy and puts it in iCloud Drive → shukr; the oldest past `keep` go.
    func make(_ context: ModelContext, trigger: String) async {
        guard !working else { return }
        working = true
        defer { working = false }
        let task = UIApplication.shared.beginBackgroundTask(withName: "iCloud copy")
        defer { if task != .invalid { UIApplication.shared.endBackgroundTask(task) } }
        await refresh()
        guard let docs = documents else {
            note(ok: false, bytes: nil, why: "iCloud Drive is off", trigger: trigger)
            return
        }
        guard let zip = await DataExport.makeCopy(context) else {
            note(ok: false, bytes: nil, why: "Couldn't make the copy", trigger: trigger)
            return
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HHmm"
        let stamp = f.string(from: .now)
        let target = docs.appending(path: Self.prefix + stamp + ".zip")
        let result = await Task.detached(priority: .utility) { () -> (Int64?, String?) in
            let fm = FileManager.default
            let bytes = (try? zip.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            do {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                // Moves the file in, and iCloud uploads it.
                try fm.setUbiquitous(true, itemAt: zip, destinationURL: target)
                ICloudCopy.prune(docs)
                return (bytes, nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }.value
        note(ok: result.1 == nil, bytes: result.0, why: result.1, trigger: trigger)
        copies = await Task.detached(priority: .utility) { ICloudCopy.list(docs) }.value
    }

    // MARK: Files

    /// shukr's copies in the folder, newest first, with iCloud's own state for each.
    nonisolated private static func list(_ docs: URL) -> [Copy] {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey, .ubiquitousItemIsUploadedKey,
                                      .ubiquitousItemIsUploadingKey, .ubiquitousItemUploadingErrorKey]
        var found: [Copy] = []
        NSFileCoordinator().coordinate(readingItemAt: docs, options: .immediatelyAvailableMetadataOnly, error: nil) { dir in
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
            for url in urls where url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == "zip" {
                let v = try? url.resourceValues(forKeys: Set(keys))
                let upload: Upload = if let e = v?.ubiquitousItemUploadingError { .failed(e.localizedDescription) }
                    else if v?.ubiquitousItemIsUploaded == true { .inICloud }
                    else if v?.ubiquitousItemIsUploading == true { .uploading }
                    else { .waiting }
                found.append(Copy(url: url, made: v?.creationDate ?? .distantPast, bytes: Int64(v?.fileSize ?? 0), upload: upload))
            }
        }
        return found.sorted { $0.made > $1.made }
    }

    /// Only shukr's own copies (by name), past the newest `keep`: never anything else in the folder.
    nonisolated private static func prune(_ docs: URL) {
        for old in list(docs).dropFirst(keep) {
            NSFileCoordinator().coordinate(writingItemAt: old.url, options: .forDeleting, error: nil) { url in
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: The log

    private static var logURL: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "YourData", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "icloud-copies.json")
    }
    private static func readLog() -> [LogLine] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        return (try? JSONDecoder().decode([LogLine].self, from: data)) ?? []
    }
    private func note(ok: Bool, bytes: Int64?, why: String?, trigger: String) {
        log.append(LogLine(at: .now, ok: ok, bytes: bytes, why: why, trigger: trigger))
        log = Array(log.suffix(60))
        if let data = try? JSONEncoder().encode(log) { try? data.write(to: Self.logURL, options: .atomic) }
        print("☁️ iCloud copy (\(trigger)): \(ok ? "saved \(bytes ?? 0) bytes" : "failed — \(why ?? "")")")
    }
}

// MARK: - The state, and its card

/// Where the iCloud backup stands, from the switch, iCloud Drive, the last try and iCloud's own state of the newest copy.
/// Your Data's top-right cloud wears its symbol; its card (`BackupCard`) says it in words.
enum BackupState {
    case off, noICloud, none, backingUp, backedUp(ICloudCopy.Copy), stale(ICloudCopy.Copy), failed(String)

    @MainActor static func now(on: Bool, _ cloud: ICloudCopy) -> BackupState {
        #if DEBUG
        // `-demoBackupState off|noICloud|none|backingUp|backedUp|stale|failed`: each state with stand-in values.
        if let demo = UserDefaults.standard.string(forKey: "demoBackupState"), on || demo == "off" {   // the switch still rules
            let copy = ICloudCopy.Copy(url: URL(fileURLWithPath: "/demo.zip"), made: .now.addingTimeInterval(-25 * 60), bytes: 2_787_884, upload: .inICloud)
            let old = ICloudCopy.Copy(url: URL(fileURLWithPath: "/demo.zip"), made: .now.addingTimeInterval(-4 * 86400), bytes: 2_787_884, upload: .inICloud)
            switch demo {
            case "off": return .off
            case "noICloud": return .noICloud
            case "none": return .none
            case "backingUp": return .backingUp
            case "stale": return .stale(old)
            case "failed": return .failed("The iCloud storage is full.")
            default: return .backedUp(copy)
            }
        }
        #endif
        guard on else { return .off }
        if cloud.availability == .off { return .noICloud }
        if cloud.working { return .backingUp }
        let newest = cloud.copies.first
        if let failed = cloud.lastFailure, failed.at > (newest?.made ?? .distantPast) { return .failed(failed.why ?? "Something went wrong.") }
        guard let newest else { return .none }
        switch newest.upload {
        case .failed(let why): return .failed(why)
        case .uploading, .waiting: return .backingUp
        case .inICloud:
            // Two days without a new one: it isn't keeping up (shukr only backs up when it's opened).
            return Date().timeIntervalSince(newest.made) > 2 * 86400 ? .stale(newest) : .backedUp(newest)
        }
    }

    var symbol: String {
        switch self {
        case .off: "icloud.slash"
        case .backedUp: "checkmark.icloud"
        case .backingUp: "icloud.and.arrow.up"   // (arrow.up.icloud isn't a symbol: it drew nothing)
        case .none: "icloud"
        case .noICloud, .stale, .failed: "exclamationmark.icloud"
        }
    }
    /// The state in a word or two: the card's status line, the button's VoiceOver label.
    var word: String {
        switch self {
        case .off: "Not backed up"
        case .noICloud: "iCloud Drive is off"
        case .none: "No backup yet"
        case .backingUp: "Backing up…"
        case .backedUp: "Backed up"
        case .stale: "Out of date"
        case .failed: "Didn't finish"
        }
    }
    var isProblem: Bool {
        switch self { case .noICloud, .stale, .failed: true; default: false }
    }
}

/// The top right's card: the state up top (symbol, word, one line), what it means, the iPhone's own backup, and the
/// one thing to do about it as a sage button at the bottom (owner). Its own view, so it follows the backup live (the
/// info card keeps the view it was opened with).
struct BackupCard: View {
    let context: ModelContext
    @AppStorage(ICloudCopy.enabledKey) private var on = false
    @State private var cloud = ICloudCopy.shared

    private var state: BackupState { BackupState.now(on: on, cloud) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            status
            // The iPhone's own backup only where it matters: while shukr's is off, it's the only one (owner: not on every state).
            if case .off = state {
                ReminderExplainer(head: sentence, points: points, explainHead: "Your iPhone's backup", explain: [
                    .init(big: "Check iCloud Backup", small: "Settings → your name → iCloud → iCloud Backup. When it's on, shukr is in it, photos too. iOS doesn't let apps see whether it's on.", symbol: "iphone", warn: false, neutral: true),
                    .init(big: "Deleting shukr deletes it", small: "Removing the app removes its data from this iPhone. Your backups keep it.", symbol: "trash", warn: false, neutral: true),
                ])
            } else {
                ReminderExplainer(head: sentence, points: points)
            }
            if let action {
                Button(action: action.run) {
                    Text(action.title)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.sage)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .overlay(Capsule().strokeBorder(Color.sage, lineWidth: 1.5))   // inside the frame: a centred stroke was cut off by the card
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    /// The state as the card's one big thing: a light word (orange when something's wrong), one grey line under it.
    /// No symbol of its own: the card's title row already wears the state's cloud (owner: not twice).
    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.word)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(state.isProblem ? Color.orange : Color.primary)
            Text(detail)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detail: String {
        switch state {
        case .off: "Your data is only on this iPhone."
        case .noICloud: "Nothing can be backed up until it's on."
        case .none: "The first backup hasn't been made."
        case .backingUp: "Uploading to your iCloud Drive."
        case .backedUp(let c): "Last backup " + YourDataPage.when(c.made).lowercasedFirstWord + " · " + YourDataPage.size(c.bytes)
        case .stale(let c): "Last backup " + YourDataPage.when(c.made).lowercasedFirstWord
        case .failed(let why): "Your last backup didn't reach iCloud. " + why
        }
    }

    /// What it means, in one or two sentences.
    private var sentence: String {
        switch state {
        case .off: "Turn it on and shukr backs up everything to your own iCloud Drive once a day. Only you can see it."
        case .noICloud: "Turn it on in Settings → your name → iCloud → iCloud Drive, and shukr backs up the next time you open it."
        case .none: "shukr backs up when you open it. You can make the first one now."
        case .backingUp: "It's usually there within a minute. You can leave this page."
        case .backedUp: "Everything in shukr is in your own iCloud Drive, and only you can see it."
        case .stale: "shukr backs up once a day when it's opened, and the last one is a few days old. Back up now to bring it up to date."
        case .failed: "Check that you're online and iCloud has room (Settings → your name → iCloud), then try again."
        }
    }

    private var points: [ReminderWhy.Point] {
        let daily = ReminderWhy.Point(big: "Every day", small: "When you open shukr, once a day. The newest \(ICloudCopy.keep) backups are kept.", symbol: "calendar", warn: false)
        let restore = ReminderWhy.Point(big: "Getting it back", small: "On a new iPhone, install shukr, then Your Data → Restore from a copy → iCloud Drive → shukr.", symbol: "arrow.counterclockwise", warn: false)
        switch state {
        case .off, .none, .backedUp, .stale: return [daily, restore]
        case .backingUp, .noICloud, .failed: return []
        }
    }

    private var action: (title: String, run: () -> Void)? {
        let backUp = { Task { await ICloudCopy.shared.make(context, trigger: "back up now") }; return () }
        switch state {
        case .off: return ("Turn On iCloud Backup", { on = true })
        case .none, .backedUp, .stale: return ("Back Up Now", { _ = backUp() })
        case .failed: return ("Try Again", { _ = backUp() })
        case .backingUp, .noICloud: return nil
        }
    }
}

private extension String {
    /// "Today, 3:12 PM" → "today, 3:12 PM" inside a sentence; "Oct 12, …" stays.
    var lowercasedFirstWord: String {
        hasPrefix("Today") || hasPrefix("Yesterday") ? prefix(1).lowercased() + dropFirst() : self
    }
}

/// Settings' Your Data row, trailing (owner): nothing while iCloud Backup is off or has no backup yet; a quiet
/// "Backed up today" while it's fine; the orange cloud + "Check backup" when something's wrong.
struct YourDataBackupTag: View {
    @AppStorage(ICloudCopy.enabledKey) private var on = false
    @State private var cloud = ICloudCopy.shared

    var body: some View {
        let state = BackupState.now(on: on, cloud)
        Group {
            switch state {
            case .off, .none: EmptyView()
            case .backingUp: Text("Backing up…").foregroundStyle(.secondary)
            case .backedUp(let c): Text("Backed up " + Self.day(c.made)).foregroundStyle(.secondary)
            case .noICloud, .stale, .failed:
                Label("Check backup", systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
        .task { if on { await cloud.refresh() } }
    }

    /// "today" / "yesterday" / "Oct 12".
    static func day(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "today" }
        if Calendar.current.isDateInYesterday(d) { return "yesterday" }
        return d.formatted(.dateTime.month(.abbreviated).day())
    }
}
