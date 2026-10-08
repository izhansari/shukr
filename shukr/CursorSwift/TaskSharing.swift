//
//  TaskSharing.swift
//  shukr
//
//  Sharing a task (owner, 2026-10-08: "allow users to share tasks with one another … sends that task and its zikr and
//  notes memos photos (via text message) … when clicked it imports that data into the app taking them to the
//  confirmation screen for adding a task").
//
//  Out: a task's hold menu → "Share task…" writes one `.shukrtask` file (JSON: the task's goal and name, its zikr whole
//  — name, full text, notes, memo, photo) and opens the share sheet with a line of text. Never a reminder, a streak or
//  history. In: the file opened in shukr (Messages → the attachment → shukr) → the app goes to the Zikr page and the
//  wheel opens `NewTaskFlow(importing:)` on its review; ✕ keeps nothing, "Add to my day" adds it. A zikr they already
//  have (a built-in, or theirs with the same name and words) is used as it is; otherwise a new one is saved with the
//  task. The file is someone else's: every field is checked and capped before it's used.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTExportedTypeDeclarations, CFBundleDocumentTypes): extension `shukrtask`.
    static let shukrTask = UTType(exportedAs: "com.betternorms.shukr.task")
}

/// What travels in the file. Version 1.
struct SharedTask: Codable, Equatable {
    var version = 1
    var taskName: String?
    var isCountMode: Bool
    var goal: Int
    var zikrName: String
    var builtInID: String?
    var fullText: String
    var notes: String
    var quickAddStep: Int
    var photo: Data?
    var memo: Data?

    init(_ task: TaskModel) {
        let zikr = task.mantra
        taskName = task.customName
        isCountMode = task.isCountMode
        goal = task.goal
        zikrName = zikr?.name ?? task.mantraName
        builtInID = zikr?.builtInID
        fullText = zikr?.fullText ?? ""
        notes = zikr?.notes ?? ""
        quickAddStep = zikr?.quickAddStep ?? 0
        photo = zikr?.imageData
        memo = zikr?.audioData
    }

    /// "Astaghfirullah · 33 a day" / "Morning azkar · 10 minutes a day".
    var summary: String {
        let title = taskName ?? zikrName
        return isCountMode ? "\(title) · \(goal.formatted()) a day" : "\(title) · \(goal) minutes a day"
    }

    /// Someone else's file: trimmed, capped, a photo that isn't one dropped.
    func checked() -> SharedTask? {
        var t = self
        guard t.version == 1 else { return nil }
        t.zikrName = String(t.zikrName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !t.zikrName.isEmpty else { return nil }
        t.taskName = t.taskName.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
        if t.taskName?.isEmpty == true { t.taskName = nil }
        t.fullText = String(t.fullText.prefix(20_000))
        t.notes = String(t.notes.prefix(20_000))
        t.goal = t.isCountMode ? min(max(t.goal, 1), 100_000) : min(max(t.goal, 1), 600)
        t.quickAddStep = min(max(t.quickAddStep, 0), 1_000)
        if let p = t.photo, p.count > 15_000_000 || UIImage(data: p) == nil { t.photo = nil }
        if let m = t.memo, m.count > 20_000_000 { t.memo = nil }
        return t
    }
}

/// A shared task ready for the review: the file's contents and the zikr it will use (one of theirs, or a new one not
/// yet in the store).
struct ImportedTask: Identifiable {
    let id = UUID()
    let task: SharedTask
    let mantra: MantraModel
}

@MainActor @Observable final class TaskSharing {
    static let shared = TaskSharing()
    /// Posted when a file arrives: PrayerTimesView clears what covers the pager and goes to the Zikr page.
    static let received = Notification.Name("taskSharingReceived")

    /// The file's task, until the wheel opens it.
    private(set) var pending: SharedTask?
    /// Set once the Zikr page is in front: the wheel opens the review then.
    private(set) var ready = false
    /// A file that couldn't be read ("This task couldn't be opened").
    var failed = false

    private static let link = "https://testflight.apple.com/join/GW5j85jk"

    // MARK: out

    /// The share sheet for `task`, over whatever is in front.
    static func share(_ task: TaskModel) {
        let shared = SharedTask(task)
        guard let url = writeFile(shared) else { return }
        let text = "A zikr task for you: \(shared.summary). Open the attachment in shukr to add it.\n\nNo shukr yet? \(link)"
        let sheet = UIActivityViewController(activityItems: [TaskShareText(text: text, subject: shared.summary), url],
                                             applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
        guard let top = topController() else { return }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }

    /// The file, in a temporary folder, named for the task ("Astaghfirullah.shukrtask").
    static func writeFile(_ shared: SharedTask) -> URL? {
        let safeName = (shared.taskName ?? shared.zikrName)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SharedTasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(safeName.isEmpty ? "Zikr task" : safeName).shukrtask")
        guard let data = try? JSONEncoder().encode(shared), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    #if DEBUG
    /// `-demoShareTask`: the share sheet for the first task. `-demoReceiveTask`: the first task written out and opened
    /// again, as a file from Messages would be (its zikr renamed, so it comes in as a new one).
    static func demo(_ context: ModelContext) async {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demoShareTask") || args.contains("-demoReceiveTask") else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard let task = (try? context.fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)])))?.first else { return }
        if args.contains("-demoShareTask") { share(task); return }
        var shared = SharedTask(task)
        shared.builtInID = nil
        shared.zikrName = "Shared " + shared.zikrName
        shared.notes = "A note from a friend."
        if let url = writeFile(shared) { TaskSharing.shared.receive(url) }
    }
    #endif

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first else { return nil }
        var top = window.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    // MARK: in

    /// A file opened in shukr. False when it isn't a shared task (another URL).
    @discardableResult
    func receive(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "shukrtask" else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            // iOS's copy in Documents/Inbox is ours to remove.
            if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size < 40_000_000, let data = try? Data(contentsOf: url),
              let task = (try? JSONDecoder().decode(SharedTask.self, from: data))?.checked() else {
            failed = true
            return true
        }
        pending = task
        ready = false
        NotificationCenter.default.post(name: Self.received, object: nil)
        return true
    }

    /// The Zikr page is in front.
    func zikrPageReady() { if pending != nil { ready = true } }

    /// The wheel takes it: the zikr it will use, found among theirs or made (not inserted) from the file.
    func take(in context: ModelContext) -> ImportedTask? {
        guard ready, let task = pending else { return nil }
        pending = nil
        ready = false
        let azkar = (try? context.fetch(FetchDescriptor<MantraModel>())) ?? []
        return ImportedTask(task: task, mantra: Self.zikr(for: task, among: azkar))
    }

    private static func zikr(for t: SharedTask, among azkar: [MantraModel]) -> MantraModel {
        if let id = t.builtInID, let built = azkar.first(where: { $0.builtInID == id }) { return built }
        let key = BuiltInAzkar.key(t.zikrName)
        if let same = azkar.first(where: { BuiltInAzkar.key($0.name) == key && ($0.isBuiltIn || $0.fullText == t.fullText) }) {
            return same
        }
        // A new zikr; a name already taken by a different one gets a number ("Morning dua 2").
        let taken = Set(azkar.map { BuiltInAzkar.key($0.name) })
        var name = t.zikrName
        var n = 2
        while taken.contains(BuiltInAzkar.key(name)) { name = "\(t.zikrName) \(n)"; n += 1 }
        let zikr = MantraModel(name: name, fullText: t.fullText, notes: t.notes)
        zikr.quickAddStep = t.quickAddStep
        zikr.imageData = t.photo
        zikr.audioData = t.memo
        return zikr
    }
}

/// The message beside the file; Mail gets it as the subject too.
private final class TaskShareText: NSObject, UIActivityItemSource {
    let text: String
    let subject: String
    init(text: String, subject: String) { self.text = text; self.subject = subject }
    func activityViewControllerPlaceholderItem(_ c: UIActivityViewController) -> Any { text }
    func activityViewController(_ c: UIActivityViewController, itemForActivityType t: UIActivity.ActivityType?) -> Any? { text }
    func activityViewController(_ c: UIActivityViewController, subjectForActivityType t: UIActivity.ActivityType?) -> String { subject }
}
