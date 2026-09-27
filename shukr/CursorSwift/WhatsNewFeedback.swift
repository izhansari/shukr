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
}

@MainActor @Observable
final class FeedbackStore {
    static let shared = FeedbackStore()

    private(set) var items: [FeedbackItem] = []

    private static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("Library/Feedback", isDirectory: true)
    }
    private static var photos: URL? { folder?.appendingPathComponent("photos", isDirectory: true) }

    private init() { load() }

    // MARK: Reading

    func unsent(for topic: String) -> FeedbackItem? { items.last { $0.topic == topic && $0.sentAt == nil } }
    func all(for topic: String) -> [FeedbackItem] { items.filter { $0.topic == topic } }
    var unsentItems: [FeedbackItem] { items.filter { $0.sentAt == nil } }

    func image(for item: FeedbackItem) -> UIImage? {
        guard let name = item.photo, let url = Self.photos?.appendingPathComponent(name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    // MARK: Writing

    /// Create or update the topic's unsent item. `photo`: nil = leave, .some(nil) = remove.
    func save(card: WhatsNewCard, kind: FeedbackItem.Kind, text: String, photo: Data??) {
        var item = unsent(for: card.id) ?? FeedbackItem(topic: card.id, topicTitle: card.title, notes: card.notes,
                                                        commits: card.commits, kind: kind, text: "",
                                                        build: BuildInfo.line)
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
            if let data = photo, let small = downscaledJPEG(data), let dir = Self.photos {
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
    func markdown(for list: [FeedbackItem], title: String = "shukr feedback") -> String {
        let when = Date().formatted(date: .abbreviated, time: .shortened)
        var lines = ["# \(title) — \(when)", "", "Build: \(BuildInfo.line)", ""]
        for item in list {
            let notes = item.notes.isEmpty ? "" : " (\(item.notes.joined(separator: ", ")))"
            lines.append("## \(item.kind.emoji) \(item.kind.label) — \(item.topicTitle)\(notes)")
            lines.append("- Topic: `\(item.topic)`")
            if !item.commits.isEmpty { lines.append("- Commits: \(item.commits.joined(separator: ", "))") }
            let tested = WhatsNew.card(id: item.topic).map { WhatsNew.isTested($0) } ?? false
            lines.append("- Status: \(item.sentAt == nil ? "unsent" : "sent \(item.sentAt!.formatted(date: .abbreviated, time: .shortened))") · \(tested ? "tested ✓" : "not ticked tested")")
            lines.append("- Written: \(item.updated.formatted(date: .abbreviated, time: .shortened)) on \(item.build)")
            if let p = item.photo { lines.append("- Photo: photos/\(p)") }
            lines.append("")
            lines.append(item.text.isEmpty ? "_(no note)_" : item.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Files

    private func load() {
        guard let url = Self.folder?.appendingPathComponent("feedback.json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([FeedbackItem].self, from: data)) ?? []
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
        // Unsent first, then sent, newest first within each — what the pull script copies.
        let ordered = unsentItems.sorted { $0.updated > $1.updated }
            + items.filter { $0.sentAt != nil }.sorted { $0.updated > $1.updated }
        try? markdown(for: ordered).write(to: dir.appendingPathComponent("feedback.md"), atomically: true, encoding: .utf8)
    }
}

// MARK: - Composer

/// Works / issue / note, a line, an optional photo. Edits the topic's unsent item.
struct FeedbackComposer: View {
    let card: WhatsNewCard
    var startKind: FeedbackItem.Kind? = nil
    var onSaved: () -> Void = {}

    @State private var store = FeedbackStore.shared
    @State private var kind: FeedbackItem.Kind = .works
    @State private var text = ""
    @State private var photoData: Data?? = nil       // nil = unchanged
    @State private var pick: PhotosPickerItem?
    @State private var loaded = false
    @FocusState private var typing: Bool

    private var existing: FeedbackItem? { store.unsent(for: card.id) }
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
                    store.save(card: card, kind: kind, text: text, photo: photoData)
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
                if let data = try? await item.loadTransferable(type: Data.self) { photoData = .some(data) }
                pick = nil
            }
        }
    }
}

/// UIActivityViewController for the Markdown + photos; `completed` only when something was done.
struct FeedbackShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (_ completed: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return vc
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
