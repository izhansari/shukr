//
//  WhatsNewFeedback.swift
//  shukr
//
//  Feedback on "What's new" topics, back to Claude (2026-09-27, notes #19). Per topic: works /
//  issue / note, a line of text and an optional photo. One UNSENT item per topic (editing it
//  updates it); "Send feedback" shares a Markdown summary of every unsent item with the photos and
//  marks them sent, so a later note on the same topic starts a new unsent item.
//
//  Stored in the app group's Library/Feedback (reachable with `devicectl device copy from`):
//  feedback.json (all items), feedback.md (the same, rendered) and photos/<id>.jpg.
//  `scripts/pull-feedback.sh` pulls it to shukrGit/feedback/<date>.md.
//
//  v3 (2026-09-27, notes #23) — a note's life: draft → sent (shared) or received (the pull script
//  writes received.json back: id → time) → addressed (a WhatsNew.json entry lists its id in
//  `addresses`) → Looks good (closed) or Still off (reopened, with a follow-up note). 👍 Works closes
//  itself once sent / received, unless something addressed it.
//

import SwiftUI
import PhotosUI

struct FeedbackItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case works, issue, note
        var label: String { switch self { case .works: "Works"; case .issue: "Issue"; case .note: "Note" } }
        var symbol: String { switch self { case .works: "hand.thumbsup.fill"; case .issue: "hand.thumbsdown.fill"; case .note: "text.bubble.fill" } }
        var emoji: String { switch self { case .works: "👍"; case .issue: "👎"; case .note: "💬" } }
        var color: Color { switch self { case .works: .green; case .issue: .orange; case .note: .sage } }
    }

    var id = UUID()
    var topic: String
    var topicTitle: String
    var notes: [String]
    var commits: [String]
    var kind: Kind
    var text: String
    var photo: String?          // file name in photos/
    var created = Date()
    var updated = Date()
    var sentAt: Date?
    var build: String
    /// "Looks good ✓" on an addressed note.
    var closedAt: Date?
    /// "Still off": the fix didn't do it; a follow-up note carries on (`followUpOf` = this id).
    var reopenedAt: Date?
    var followUpOf: UUID?

    init(topic: String, topicTitle: String, notes: [String], commits: [String], kind: Kind, text: String, build: String) {
        self.topic = topic; self.topicTitle = topicTitle; self.notes = notes; self.commits = commits
        self.kind = kind; self.text = text; self.build = build
    }

    /// Every field optional with a default, so a file written by an older or newer build still
    /// reads (a failed decode used to lose the whole list).
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
        created = (try? c.decodeIfPresent(Date.self, forKey: .created)) ?? Date()
        updated = (try? c.decodeIfPresent(Date.self, forKey: .updated)) ?? created
        sentAt = try? c.decodeIfPresent(Date.self, forKey: .sentAt)
        build = (try? c.decodeIfPresent(String.self, forKey: .build)) ?? ""
        closedAt = try? c.decodeIfPresent(Date.self, forKey: .closedAt)
        reopenedAt = try? c.decodeIfPresent(Date.self, forKey: .reopenedAt)
        followUpOf = try? c.decodeIfPresent(UUID.self, forKey: .followUpOf)
    }
}

/// Where a note stands (in order of how much it needs you).
enum FeedbackState {
    case draft                          // written, not sent
    case toCheck(WhatsNewEntry)         // a change in this build addresses it
    case received(Date)                 // Claude has it (the pull script said so)
    case sent(Date)                     // shared, not yet pulled
    case closed                         // looks good / 👍 works
    case reopened                       // still off — its follow-up note carries on

    var isOpen: Bool { if case .closed = self { false } else if case .reopened = self { false } else { true } }
}

@MainActor @Observable
final class FeedbackStore {
    static let shared = FeedbackStore()

    private(set) var items: [FeedbackItem] = []
    /// From received.json, written by scripts/pull-feedback.sh: id → when Claude pulled it.
    private(set) var received: [UUID: Date] = [:]

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("Library/Feedback", isDirectory: true)
    }
    private static var photos: URL? { folder?.appendingPathComponent("photos", isDirectory: true) }

    /// feedback.md is rewritten at launch too, so a pull never copies states older than the app's.
    private init() { load(); loadReceived(); writeMarkdown() }

    // MARK: Reading

    func isSent(_ item: FeedbackItem) -> Bool { item.sentAt != nil || received[item.id] != nil }
    /// Still a draft: not sent / received, not closed / reopened, and not addressed by a change
    /// (an addressed note reached Claude one way or another — it's "to check", never re-edited).
    private func isDraft(_ item: FeedbackItem) -> Bool {
        !isSent(item) && item.closedAt == nil && item.reopenedAt == nil && WhatsNew.addressing(item.id) == nil
    }
    /// Any draft on the topic (for "unsent" badges / sections; a received / sent note isn't edited
    /// again — a new one starts fresh).
    func unsent(for topic: String) -> FeedbackItem? { items.last { $0.topic == topic && isDraft($0) } }
    /// THE draft a composer edits: the topic's plain draft, or the draft following up one note
    /// ("Still off"). One lookup for save() and the composer, so neither loads one and writes the
    /// other (review, 2026-09-27: a follow-up duplicated a plain draft and lost its photo).
    func draft(for topic: String, followUpOf: UUID? = nil) -> FeedbackItem? {
        if let followUpOf { return items.last { $0.followUpOf == followUpOf && isDraft($0) } }
        return items.last { $0.topic == topic && isDraft($0) && $0.followUpOf == nil }
    }
    func all(for topic: String) -> [FeedbackItem] { items.filter { $0.topic == topic } }
    var unsentItems: [FeedbackItem] { items.filter(isDraft) }

    func state(_ item: FeedbackItem) -> FeedbackState {
        if item.reopenedAt != nil { return .reopened }
        if item.closedAt != nil { return .closed }
        if let fix = WhatsNew.addressing(item.id) { return .toCheck(fix) }
        if !isSent(item) { return .draft }
        if item.kind == .works { return .closed }        // nothing to follow up
        if let r = received[item.id] { return .received(r) }
        return .sent(item.sentAt ?? item.updated)
    }
    var toCheck: [(item: FeedbackItem, fix: WhatsNewEntry)] {
        items.compactMap { item in if case .toCheck(let fix) = state(item) { (item, fix) } else { nil } }
    }
    /// The topic's note that needs checking, if any.
    func toCheck(for topic: String) -> Bool { toCheck.contains { $0.item.topic == topic } }

    func image(for item: FeedbackItem) -> UIImage? {
        guard let name = item.photo, let url = Self.photos?.appendingPathComponent(name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: Writing

    /// Create or update the topic's unsent item. `photo`: nil = leave, .some(nil) = remove.
    func save(card: WhatsNewCard, kind: FeedbackItem.Kind, text: String, photo: Data??, followUpOf: UUID? = nil) {
        let fresh = FeedbackItem(topic: card.id, topicTitle: card.title, notes: card.notes,
                                 commits: card.commits, kind: kind, text: "", build: BuildInfo.line)
        // A "Still off" follow-up is always its own note (its own id — a later fix lists that id),
        // never merged into a draft already on the topic. Re-saving the same follow-up updates it.
        var item = draft(for: card.id, followUpOf: followUpOf) ?? fresh
        if let followUpOf { item.followUpOf = followUpOf }
        item.topicTitle = card.title
        item.notes = card.notes
        item.commits = card.commits
        item.kind = kind
        item.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        item.updated = Date()
        item.build = BuildInfo.line
        if let photo {
            if let old = item.photo { removePhoto(old) }
            item.photo = nil
            if let small = photo, let dir = Self.photos {             // already downscaled by the composer
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = "\(item.id.uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970)).jpg"
                if (try? small.write(to: dir.appendingPathComponent(name))) != nil { item.photo = name }
            }
        }
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        persist()
    }

    func delete(_ item: FeedbackItem) {
        if let p = item.photo { removePhoto(p) }
        items.removeAll { $0.id == item.id }
        persist()
    }

    /// "Looks good ✓".
    func close(_ item: FeedbackItem) { update(item.id) { $0.closedAt = Date() } }
    /// "Still off": reopened; the caller opens a follow-up note (`save(…, followUpOf:)`).
    func reopen(_ item: FeedbackItem) { update(item.id) { $0.reopenedAt = Date(); $0.closedAt = nil } }

    private func update(_ id: UUID, _ change: (inout FeedbackItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
        persist()
    }

    /// "Still off" cancelled with nothing written: back to "to check".
    func undoReopen(_ id: UUID) {
        guard !items.contains(where: { $0.followUpOf == id }) else { return }
        update(id) { $0.reopenedAt = nil }
    }

    /// Pick up a received.json the pull script wrote while the app was running.
    func reloadReceived() { loadReceived(); writeMarkdown() }

    func markSent(_ ids: Set<UUID>) {
        let now = Date()
        for i in items.indices where ids.contains(items[i].id) { items[i].sentAt = now }
        persist()
    }

    private func removePhoto(_ name: String) {
        guard let url = Self.photos?.appendingPathComponent(name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Markdown

    /// One summary for Claude: build, then each item — kind, topic, notes #, commits, status, note.
    /// `photoPrefix`: "photos/" in the stored copy (next to its folder); "" when shared (the
    /// photos travel as files with exactly those names).
    func markdown(for list: [FeedbackItem], title: String = "shukr feedback", photoPrefix: String = "photos/") -> String {
        let when = Date().formatted(date: .abbreviated, time: .shortened)
        var lines = ["# \(title) — \(when)", "", "Build: \(BuildInfo.line)", ""]
        for item in list {
            let notes = item.notes.isEmpty ? "" : " (\(item.notes.joined(separator: ", ")))"
            lines.append("## \(item.kind.emoji) \(item.kind.label) — \(item.topicTitle)\(notes)")
            lines.append("- Topic: `\(item.topic)` · Id: `\(item.id.uuidString)`")
            if let f = item.followUpOf { lines.append("- Follow-up of: `\(f.uuidString)` (still off after its fix)") }
            if !item.commits.isEmpty { lines.append("- Commits: \(item.commits.joined(separator: ", "))") }
            let tested = WhatsNew.card(id: item.topic).map { WhatsNew.isTested($0) } ?? false
            lines.append("- Status: \(statusLine(item)) · \(tested ? "tested ✓" : "not ticked tested")")
            lines.append("- Written: \(item.updated.formatted(date: .abbreviated, time: .shortened)) on \(item.build)")
            if let p = item.photo { lines.append("- Photo: \(photoPrefix)\(p)") }
            lines.append("")
            lines.append(item.text.isEmpty ? "_(no note)_" : item.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func statusLine(_ item: FeedbackItem) -> String {
        let t = { (d: Date) in d.formatted(date: .abbreviated, time: .shortened) }
        switch state(item) {
        case .draft: return "unsent"
        case .toCheck(let fix): return "addressed by \(fix.commit) — to check"
        case .received(let d): return "received \(t(d))"
        case .sent(let d): return "sent \(t(d))"
        case .closed: return item.closedAt.map { "closed \(t($0))" } ?? "closed (works)"
        case .reopened: return "reopened \(item.reopenedAt.map(t) ?? "")"
        }
    }

    /// What "Send feedback" shares: the Markdown as a .md file plus each photo as a file named
    /// as the Markdown references it — so AirDrop / Files / the Claude app keep them together.
    func shareFiles(for list: [FeedbackItem]) -> [URL] {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shukr-feedback-\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        let md = dir.appendingPathComponent("shukr-feedback-\(stamp).md")
        if (try? markdown(for: list, photoPrefix: "").write(to: md, atomically: true, encoding: .utf8)) != nil { urls.append(md) }
        for item in list {
            guard let name = item.photo, let from = Self.photos?.appendingPathComponent(name) else { continue }
            let to = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: to)
            if (try? FileManager.default.copyItem(at: from, to: to)) != nil { urls.append(to) }
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
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appendingPathComponent("feedback.json.bad-\(stamp)")
            try? FileManager.default.moveItem(at: url, to: aside)
            print("⚠️ feedback.json unreadable (\(error)); moved to \(aside.lastPathComponent)")
            items = []
        }
    }

    /// `{"received": {"<id>": "<ISO 8601>"}}` — scripts/pull-feedback.sh writes it with
    /// `devicectl device copy to` (dev builds; a TestFlight install can't be written to).
    private func loadReceived() {
        guard let url = Self.folder?.appendingPathComponent("received.json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let map = obj["received"] as? [String: String] else { return }
        var result: [UUID: Date] = [:]
        for (id, when) in map {
            if let uuid = UUID(uuidString: id), let date = WhatsNew.iso.date(from: when) { result[uuid] = date }
        }
        received = result
    }

    private func persist() {
        guard let dir = Self.folder else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: dir.appendingPathComponent("feedback.json"), options: .atomic)
        }
        writeMarkdown()
    }

    /// feedback.md: what the pull script copies. After every change, at launch and after reading
    /// received.json (states depend on it).
    private func writeMarkdown() {
        guard let dir = Self.folder, FileManager.default.fileExists(atPath: dir.path) else { return }
        // Unsent first, then everything else (sent, received, to check, closed, reopened — each
        // with its state), newest first within each — what the pull script copies.
        let drafts = unsentItems
        let draftIDs = Set(drafts.map(\.id))
        let ordered = drafts.sorted { $0.updated > $1.updated }
            + items.filter { !draftIDs.contains($0.id) }.sorted { $0.updated > $1.updated }
        try? markdown(for: ordered).write(to: dir.appendingPathComponent("feedback.md"), atomically: true, encoding: .utf8)
    }
}

// MARK: - Composer

/// Works / issue / note, a line, an optional photo. Edits the topic's unsent item.
struct FeedbackComposer: View {
    let card: WhatsNewCard
    var startKind: FeedbackItem.Kind? = nil
    /// "Still off": the note this one follows up.
    var followUpOf: UUID? = nil
    var onSaved: () -> Void = {}

    @State private var store = FeedbackStore.shared
    @State private var kind: FeedbackItem.Kind = .works
    @State private var text = ""
    @State private var photoData: Data?? = nil       // nil = unchanged
    @State private var pick: PhotosPickerItem?
    @State private var loaded = false
    @FocusState private var typing: Bool

    private var existing: FeedbackItem? { store.draft(for: card.id, followUpOf: followUpOf) }
    private var shownImage: UIImage? {
        if let photoData { return photoData.flatMap(UIImage.init(data:)) }
        return existing.flatMap(store.image(for:))
    }
    private var changed: Bool {
        guard let e = existing else { return true }
        return e.kind != kind || e.text != text.trimmingCharacters(in: .whitespacesAndNewlines) || photoData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(FeedbackItem.Kind.allCases, id: \.self) { k in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { kind = k }
                    } label: {
                        Label(k.label, systemImage: k.symbol)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(kind == k ? k.color : Color.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(kind == k ? k.color.opacity(0.14) : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.selection, trigger: kind)

            TextField(kind == .works ? "Anything to add? (optional)" : "What happened?", text: $text, axis: .vertical)
                .lineLimit(2...6)
                .focused($typing)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))

            HStack(spacing: 12) {
                if let ui = shownImage {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("Remove", role: .destructive) { photoData = .some(nil) }
                        .font(.subheadline)
                } else {
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label("Add a photo", systemImage: "photo.badge.plus")
                            .font(.subheadline)
                    }
                    .tint(.secondary)
                }
                Spacer()
                Button {
                    typing = false
                    store.save(card: card, kind: kind, text: text, photo: photoData, followUpOf: followUpOf)
                    photoData = nil
                    triggerSomeVibration(type: .success)
                    onSaved()
                } label: {
                    Text(existing == nil ? "Save" : "Update")
                        .fontWeight(.semibold)
                        .foregroundStyle(changed ? Color.green : Color.secondary)
                }
                .disabled(!changed)
            }
            if let e = existing {
                Text("Not sent yet · saved \(e.updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing { kind = e.kind; text = e.text }
            if let startKind { kind = startKind }
            if startKind == .issue || startKind == .note { typing = true }
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let small = await downscaledJPEG(data) {
                    photoData = .some(small)
                }
                pick = nil
            }
        }
    }
}

/// UIActivityViewController for the Markdown + photos; `completed` only when something was done.
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
