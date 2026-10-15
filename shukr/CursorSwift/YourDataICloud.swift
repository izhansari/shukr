import Foundation
import SwiftData
import UIKit

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
