//
//  WhatsNewFeedback.swift
//  shukr
//
//  What the owner says back from What's new (v4, 2026-09-29): an answer on something he asked for
//  (Works / Not yet) or a comment on any change — words plus any number of photos (drawn on or not) and
//  short videos. Nothing he says disappears: it sits in "Your answers" (saved on this phone → sent →
//  Bradley has it) and always in "Everything you've said".
//
//  Stored in the app group's Library/Feedback (reachable with `devicectl device copy from`):
//  feedback.json (every item), feedback.md (the same, rendered for Bradley) and photos/ (photos AND
//  videos — the folder kept its v1 name). `scripts/pull-feedback.sh` pulls them and writes
//  received.json back ({"received": {id: when first pulled}, "seen": {id: the `updated` it pulled}}).
//

import SwiftUI

struct FeedbackItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        /// works = "Works"; issue = "Not yet" (v1–v3 called it Issue); note = a comment; idea = a new idea
        /// (ask wn-ideas: from a card or from the page's "New idea"). An older build reads an idea as a note.
        /// ship = "Ready for TestFlight" from Next build (ask wn-next-build; `commits` = the changes in it).
        /// decision = his pick on a question (ask wn-decisions; `decision` + `option`, the note in `text`).
        /// An older build reads it as a comment.
        case works, issue, note, idea, ship, decision
        var label: String {
            switch self {
            case .works: "Works"; case .issue: "Not yet"; case .note: "Comment"; case .idea: "Idea"; case .ship: "Ready for TestFlight"
            case .decision: "Decision"
            }
        }
        var symbol: String {
            switch self {
            case .works: "checkmark.circle.fill"; case .issue: "pencil.circle.fill"; case .note: "text.bubble.fill"
            case .idea: "lightbulb.fill"; case .ship: "paperplane.fill"; case .decision: "checklist"
            }
        }
        var emoji: String { switch self { case .works: "👍"; case .issue: "👎"; case .note: "💬"; case .idea: "💡"; case .ship: "🚀"; case .decision: "🗳" } }
        var color: Color {
            switch self {
            case .works: .green; case .issue: .orange; case .note, .ship, .decision: .sage; case .idea: Color(red: 0.72, green: 0.53, blue: 0.08)
            }
        }
        /// An answer on an ask (Works / Not yet) — comments and ideas never are.
        var isVerdict: Bool { self == .works || self == .issue }
    }

    var id = UUID()
    var topic: String
    var topicTitle: String
    var notes: [String]
    var commits: [String]
    var kind: Kind
    var text: String
    /// v1–v3's single photo (still read; new items use `media`).
    var photo: String?
    /// Photos (.jpg) and videos (.mp4) in photos/, in the order he added them.
    var media: [String]?
    /// The ask this answers (Works / Not yet).
    var ask: String?
    /// The change it was given on (an idea: the card it came from, if any).
    var onEntry: String?
    /// An idea's area (WhatsNew.areaOrder).
    var area: String?
    /// A decision's id and the option he picked (Kind.decision).
    var decision: String?
    var option: String?
    var created = Date()
    var updated = Date()
    var sentAt: Date?
    var build: String
    // v3, kept so old notes still read and migrate:
    var closedAt: Date?
    var reopenedAt: Date?
    var followUpOf: UUID?
    var followUpOfEntry: String?

    init(topic: String, topicTitle: String, kind: Kind, text: String, build: String) {
        self.topic = topic; self.topicTitle = topicTitle; self.notes = []; self.commits = []
        self.kind = kind; self.text = text; self.build = build
    }

    /// Every field optional with a default, so a file written by an older or newer build still reads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        topic = (try? c.decodeIfPresent(String.self, forKey: .topic)) ?? "unknown"
        topicTitle = (try? c.decodeIfPresent(String.self, forKey: .topicTitle)) ?? topic
        notes = (try? c.decodeIfPresent([String].self, forKey: .notes)) ?? []
        commits = (try? c.decodeIfPresent([String].self, forKey: .commits)) ?? []
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .note
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        photo = try? c.decodeIfPresent(String.self, forKey: .photo)
        media = try? c.decodeIfPresent([String].self, forKey: .media)
        ask = try? c.decodeIfPresent(String.self, forKey: .ask)
        onEntry = try? c.decodeIfPresent(String.self, forKey: .onEntry)
        area = try? c.decodeIfPresent(String.self, forKey: .area)
        decision = try? c.decodeIfPresent(String.self, forKey: .decision)
        option = try? c.decodeIfPresent(String.self, forKey: .option)
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date()
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? created
        sentAt = try? c.decodeIfPresent(Date.self, forKey: .sentAt)
        build = (try? c.decodeIfPresent(String.self, forKey: .build)) ?? ""
        closedAt = try? c.decodeIfPresent(Date.self, forKey: .closedAt)
        reopenedAt = try? c.decodeIfPresent(Date.self, forKey: .reopenedAt)
        followUpOf = try? c.decodeIfPresent(UUID.self, forKey: .followUpOf)
        followUpOfEntry = try? c.decodeIfPresent(String.self, forKey: .followUpOfEntry)
    }

    /// Photos and videos, old single photo included.
    var attachments: [String] { media ?? (photo.map { [$0] } ?? []) }
    /// What it's about, in a few words (the change's headline, else the feature).
    var about: String {
        if kind == .ship { return "Next build · \(commits.count) change\(commits.count == 1 ? "" : "s")" }
        if kind == .decision, let id = decision {
            let d = WhatsNew.decision(id)
            let label = option.flatMap { d?.option($0)?.label }
            return "\(d?.question ?? id) → \(option == nil ? "un-picked (back to waiting)" : label ?? option ?? "?")"
        }
        if let e = onEntry.flatMap(WhatsNew.entry) { return kind == .idea ? "Idea from: \(e.short)" : e.short }
        return kind == .idea ? (area.map { "Idea · \($0)" } ?? "Idea") : topicTitle
    }
    var isAnswer: Bool { kind.isVerdict && ask != nil }
    /// A v1–v3 note: no change attached, and not one of v4's card-less kinds (a top-of-page idea, a Ready
    /// for TestFlight note) — "no card" alone doesn't mean old.
    var isV3Note: Bool { onEntry == nil && decision == nil && (kind == .works || kind == .issue || kind == .note) }
}

/// Where something he said stands.
enum NoteState: Equatable {
    case saved                  // on the phone; the next pull (or Send) takes it
    case sent(Date)             // shared from the phone
    case received(Date)         // Bradley has it (the pull wrote received.json)
}

@MainActor @Observable
final class FeedbackStore {
    static let shared = FeedbackStore()

    private(set) var items: [FeedbackItem] = [] { didSet { revision &+= 1 } }
    /// Bumps whenever `items` changes: what WhatsNew's cached ask states are keyed on (ask wn-speed).
    private(set) var revision = 0
    /// From received.json: id → when it was first pulled, and the `updated` the latest pull saw.
    private(set) var received: [UUID: Date] = [:]
    private(set) var seen: [UUID: Date] = [:]

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("Library/Feedback", isDirectory: true)
    }
    static var mediaFolder: URL? { folder?.appendingPathComponent("photos", isDirectory: true) }

    /// feedback.md is written on the next turn, not in init: writing it asks WhatsNew for ask states,
    /// which read `FeedbackStore.shared` — from inside its own initialiser that's a recursive
    /// dispatch_once (it crashed opening What's new once).
    private init() {
        load(); loadReceived()
        scheduleMarkdown()
        // Going to the background: write what's still waiting on the debounce now — a pull while the
        // app is suspended would otherwise read an old feedback.md / state.json (Ben's review).
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                #if DEBUG
                if WhatsNewPerf.on { print("WNPERF background: pending feedback.md=\(FeedbackStore.shared.markdownWork != nil)") }
                #endif
                FeedbackStore.shared.flush()
            }
        }
    }

    /// Anything debounced, written now; returns once the files are on disk.
    func flush() {
        if markdownWork != nil {
            markdownWork?.cancel()
            markdownWork = nil
            writeMarkdown()
            #if DEBUG
            if WhatsNewPerf.on { print("WNPERF flush: feedback.md written on going to the background") }
            #endif
        }
        WhatsNew.flushState()
        Self.writer.sync {}
    }

    // MARK: Reading

    func state(_ item: FeedbackItem) -> NoteState {
        // Pulled after its last edit.
        if let s = seen[item.id], s.addingTimeInterval(1) >= item.updated { return .received(received[item.id] ?? s) }
        if seen[item.id] == nil, let r = received[item.id], r >= item.updated { return .received(r) }
        if let s = item.sentAt, s.addingTimeInterval(1) >= item.updated { return .sent(s) }
        return .saved
    }

    func stateLine(_ item: FeedbackItem) -> String {
        switch state(item) {
        case .saved: return seen[item.id] != nil || received[item.id] != nil
            ? "Edited · not picked up yet" : "Saved on this phone · not picked up yet"
        case .sent(let d): return "Sent \(WhatsNew.whenLabel(d))"
        case .received(let d): return "Bradley has it · \(WhatsNew.whenLabel(d))"
        }
    }

    /// "Your answers": what the team hasn't read yet, plus what they picked up in the last day.
    var pending: [FeedbackItem] {
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        return items.filter { item in
            // v1–v3 notes (no change attached) that the team has: history, in Everything you've said.
            if case .received(let d) = state(item) { return !item.isV3Note && d > dayAgo }
            return true
        }
        .sorted { $0.updated > $1.updated }
    }
    /// Not yet sent or pulled (what Send shares).
    var unsent: [FeedbackItem] { items.filter { state($0) == .saved } }

    /// His answer on this change of this ask, if it can still be edited in place (not picked up yet).
    func editableAnswer(ask: String, entry: String) -> FeedbackItem? {
        items.last { $0.ask == ask && $0.onEntry == entry && $0.kind.isVerdict && state($0) == .saved }
    }

    func mediaURL(_ name: String) -> URL? { Self.mediaFolder?.appendingPathComponent(name) }
    static func isVideo(_ name: String) -> Bool { ["mp4", "mov", "m4v"].contains((name as NSString).pathExtension.lowercased()) }

    // MARK: Writing

    /// Works / Not yet on an ask's change, a comment (.note), or an idea (.idea: `entry` = the card it came
    /// from, or nil from the page's "New idea"; `area` its area). Edits `existing` when given.
    @discardableResult
    func save(existing: FeedbackItem? = nil, entry: WhatsNewEntry?, ask: String?, kind: FeedbackItem.Kind,
              text: String, media: [String], area: String? = nil) -> FeedbackItem {
        let topic = entry?.topic ?? "idea"
        let topicTitle = entry.map { WhatsNew.topicTitle($0.topic) } ?? "Idea"
        var item = existing ?? FeedbackItem(topic: topic, topicTitle: topicTitle, kind: kind, text: "", build: BuildInfo.line)
        let removed = Set(item.attachments).subtracting(media)
        item.kind = kind
        item.ask = kind.isVerdict ? ask : nil
        item.onEntry = entry?.id
        item.area = kind == .idea ? (area ?? entry.map { WhatsNew.area($0.topic) }) : nil
        item.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        item.media = media
        item.photo = nil
        item.notes = entry?.notes.map { [$0] } ?? []
        item.commits = entry.map { [$0.id] } ?? []
        item.topic = topic
        item.topicTitle = topicTitle
        item.updated = Date()
        item.build = BuildInfo.line
        removed.forEach(removeMedia)
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        persist()
        WhatsNew.writeState()
        return item
    }

    /// His pick on a decision (Decisions page), with an optional note. Edits `existing` while it can still be
    /// edited in place (not picked up yet); otherwise a new answer (the newest one counts).
    @discardableResult
    /// `option` nil = he un-picked it: the decision goes back to waiting (ask decision-undo).
    func saveDecision(_ d: WhatsNewDecision, option: String?, text: String, existing: FeedbackItem? = nil) -> FeedbackItem {
        var item = existing.flatMap { state($0) == .saved ? $0 : nil }
            ?? FeedbackItem(topic: "decision", topicTitle: "Decision", kind: .decision, text: "", build: BuildInfo.line)
        item.kind = .decision
        item.decision = d.id
        item.option = option
        item.area = d.area
        item.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updated = Date()
        item.build = BuildInfo.line
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        persist()
        WhatsNew.writeState()
        return item
    }

    /// "I'm happy with this — ready for TestFlight" (Next build): a note for the team, not a gate — Frank
    /// confirms with him before uploading; nothing uploads from the phone.
    @discardableResult
    func saveReadyForTestFlight(changes: [WhatsNewEntry], openAsks: Int) -> FeedbackItem {
        var item = FeedbackItem(topic: "build", topicTitle: "Next build", kind: .ship,
                                text: "Ready for TestFlight" + (openAsks > 0 ? " (\(openAsks) ask\(openAsks == 1 ? "" : "s") unanswered)" : ""),
                                build: BuildInfo.line)
        item.commits = changes.map(\.id)
        items.append(item)
        persist()
        WhatsNew.writeState()
        return item
    }

    /// The newest "Ready for TestFlight" since the last upload.
    var readyForTestFlight: FeedbackItem? {
        let after = WhatsNew.lastBuild?.date ?? .distantPast
        return items.filter { $0.kind == .ship && $0.created > after }.max { $0.created < $1.created }
    }

    func delete(_ item: FeedbackItem) {
        item.attachments.forEach(removeMedia)
        items.removeAll { $0.id == item.id }
        persist()
        WhatsNew.writeState()
    }

    /// A new photo or video file in photos/ (the composer calls this as soon as one is added).
    func storeMedia(_ data: Data, ext: String) -> String? {
        guard let dir = Self.mediaFolder else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.prefix(8).lowercased())-\(Int(Date().timeIntervalSince1970)).\(ext)"
        return (try? data.write(to: dir.appendingPathComponent(name))) != nil ? name : nil
    }
    func storeMedia(file: URL, ext: String) -> String? {
        guard let dir = Self.mediaFolder else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.prefix(8).lowercased())-\(Int(Date().timeIntervalSince1970)).\(ext)"
        return (try? FileManager.default.moveItem(at: file, to: dir.appendingPathComponent(name))) != nil ? name : nil
    }
    /// Files added in a composer that was cancelled (never part of a saved item).
    func discardMedia(_ names: [String]) {
        let kept = Set(items.flatMap(\.attachments))
        names.filter { !kept.contains($0) }.forEach(removeMedia)
    }
    private func removeMedia(_ name: String) {
        guard let url = mediaURL(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Pick up a received.json the pull script wrote while the app was running.
    func reloadReceived() { loadReceived(); scheduleMarkdown() }

    func markSent(_ ids: Set<UUID>) {
        let now = Date()
        for i in items.indices where ids.contains(items[i].id) { items[i].sentAt = now }
        persist()
    }

    // MARK: Markdown (for Bradley)

    /// Each item: what it's about, the answer, where it stands, his words, its files. `mediaPrefix`:
    /// "photos/" in the stored copy; "" when shared (the files travel with exactly those names).
    func markdown(for list: [FeedbackItem], title: String = "shukr feedback", mediaPrefix: String = "photos/") -> String {
        let when = Date().formatted(date: .abbreviated, time: .shortened)
        var lines = ["# \(title) — \(when)", "", "Build: \(BuildInfo.line)", ""]
        for item in list {
            if item.kind == .ship {
                lines.append("## 🚀 Ready for TestFlight")
                let since = WhatsNew.lastBuild.map { "since build \($0.number)" } ?? "so far"
                lines.append("- \(item.commits.count) change(s) \(since): " + item.commits.map { "`\($0)`" }.joined(separator: ", "))
            } else if item.kind == .decision {
                let d = item.decision.flatMap(WhatsNew.decision)
                if let option = item.option {
                    let label = d?.option(option)?.label ?? ""
                    lines.append("## 🗳 Decision — \(item.decision ?? "?"): \(option) — \(label)")
                } else {
                    lines.append("## 🗳 Decision — \(item.decision ?? "?"): un-picked (back to waiting)")
                }
                if let q = d?.question { lines.append("- Question: \(q)") }
            } else if item.kind == .idea {
                lines.append("## \(item.kind.emoji) Idea — \(item.area ?? "no area")")
                if let e = item.onEntry {
                    lines.append("- From: `\(e)` (\(WhatsNew.entry(e)?.short ?? WhatsNew.topicTitle(item.topic)))")
                }
            } else {
                lines.append("## \(item.kind.emoji) \(item.kind.label) — \(item.about)")
            }
            var meta = item.kind == .idea || item.kind == .ship || item.kind == .decision ? [] : ["Feature: `\(item.topic)`"]
            if let e = item.onEntry, item.kind != .idea { meta.append("Change: `\(e)`") }
            if let a = item.ask { meta.append("Ask: `\(a)`") }
            meta.append("Id: `\(item.id.uuidString)`")
            lines.append("- " + meta.joined(separator: " · "))
            if let a = item.ask.flatMap(WhatsNew.ask), let words = a.words, !words.isEmpty {
                lines.append("- He asked: “\(words.prefix(160))\(words.count > 160 ? "…" : "")”")
            }
            lines.append("- Status: \(stateLine(item))")
            lines.append("- Written: \(item.updated.formatted(date: .abbreviated, time: .shortened)) on \(item.build)")
            for m in item.attachments { lines.append("- \(Self.isVideo(m) ? "Video" : "Photo"): \(mediaPrefix)\(m)") }
            lines.append("")
            lines.append(item.text.isEmpty ? "_(no words)_" : item.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Send: the Markdown as a .md file plus every photo / video, named as the Markdown names them.
    func shareFiles(for list: [FeedbackItem]) -> [URL] {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shukr-feedback-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        let md = dir.appendingPathComponent("shukr-feedback-\(stamp).md")
        if (try? markdown(for: list, mediaPrefix: "").write(to: md, atomically: true, encoding: .utf8)) != nil { urls.append(md) }
        for name in list.flatMap(\.attachments) {
            guard let from = mediaURL(name) else { continue }
            let to = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: to)
            if (try? FileManager.default.copyItem(at: from, to: to)) != nil { urls.append(to) }
        }
        // The watch's pinch log, when there is one (watch-pinch-log: the only pinch watch is a TestFlight one).
        if let log = WatchSync.pinchLog {
            let to = dir.appendingPathComponent("watch-pinch.log")
            try? FileManager.default.removeItem(at: to)
            if (try? FileManager.default.copyItem(at: log, to: to)) != nil { urls.append(to) }
        }
        return urls
    }

    // MARK: Files

    private func load() {
        guard let url = Self.folder?.appendingPathComponent("feedback.json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            items = try decoder.decode([FeedbackItem].self, from: data)
        } catch {
            // Never overwrite what can't be read: move it aside and start a new list.
            let aside = url.deletingLastPathComponent().appendingPathComponent("feedback.json.bad-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            print("⚠️ feedback.json unreadable (\(error)); moved to \(aside.lastPathComponent)")
            items = []
        }
    }

    private func loadReceived() {
        guard let url = Self.folder?.appendingPathComponent("received.json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        func map(_ key: String) -> [UUID: Date] {
            var out: [UUID: Date] = [:]
            for (id, when) in obj[key] as? [String: String] ?? [:] {
                if let uuid = UUID(uuidString: id), let date = WhatsNew.iso.date(from: when) { out[uuid] = date }
            }
            return out
        }
        received = map("received")
        seen = map("seen")
    }

    /// feedback.json at once (it's his answers), but written off the main thread; feedback.md follows,
    /// debounced (ask wn-speed: opening and every save used to rewrite it on the main thread).
    private func persist() {
        guard let dir = Self.folder else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            let url = dir.appendingPathComponent("feedback.json")
            Self.writer.async {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
        scheduleMarkdown()
    }

    /// One serial queue for the folder's files, so writes land in order.
    static let writer = DispatchQueue(label: "shukr.feedback.writer", qos: .utility)
    fileprivate(set) var markdownWork: Task<Void, Never>?
    /// feedback.md about a second after the last change (not per keystroke / save / open); the text is
    /// built here, the file written on `writer`.
    private func scheduleMarkdown() {
        markdownWork?.cancel()
        markdownWork = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.markdownWork = nil
            self?.writeMarkdown()
        }
    }

    /// feedback.md: what the pull copies. Not picked up yet first, then the rest; then the asks still
    /// waiting for him.
    private func writeMarkdown() {
        #if DEBUG
        WhatsNewPerf.markdown += 1
        #endif
        guard let dir = Self.folder, FileManager.default.fileExists(atPath: dir.path) else { return }
        // Not picked up yet first, a "Ready for TestFlight" at the very top.
        let fresh = items.filter { state($0) == .saved }
            .sorted { ($0.kind == .ship ? 1 : 0, $0.updated) > ($1.kind == .ship ? 1 : 0, $1.updated) }
        let freshIDs = Set(fresh.map(\.id))
        let rest = items.filter { !freshIDs.contains($0.id) }.sorted { $0.updated > $1.updated }
        var md = markdown(for: fresh + rest)
        let open = WhatsNew.openAsks()
        md += "\n## Waiting for him (Your asks)\n\n"
        md += open.isEmpty ? "_(nothing)_\n"
            : open.map { "- `\($0.ask.id)` — \($0.latest.short) (`\($0.latest.id)`)" }.joined(separator: "\n") + "\n"
        let waiting = WhatsNew.openDecisions()
        md += "\n## Decisions waiting for him\n\n"
        md += waiting.isEmpty ? "_(nothing)_\n" : waiting.map { "- `\($0.id)` — \($0.question)" }.joined(separator: "\n") + "\n"
        let url = dir.appendingPathComponent("feedback.md")
        Self.writer.async { try? md.write(to: url, atomically: true, encoding: .utf8) }
    }
}

/// UIActivityViewController for the Markdown + files; `completed` only when something was done.
struct FeedbackShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// `activity`: where it went (Copy is told apart: copying isn't sending).
    let onFinish: (_ completed: Bool, _ activity: UIActivity.ActivityType?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activity, completed, _, _ in onFinish(completed, activity) }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
