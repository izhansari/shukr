//
//  WhatsNew.swift
//  shukr
//
//  "What's new" — what changed and how to try it, so the owner knows what to test in the build
//  they're holding. Tap the build line (bottom of the ☰ menu and of Settings). Only in DEBUG and
//  TestFlight builds, never App Store ones.
//
//  v2 (2026-09-27, notes #19): one card per FEATURE (topic), not per commit. The card says what the
//  feature is now, when it last changed, how many changes, a thumbnail and the tested circle; tap →
//  the try-it steps, screenshots, the commits as a timeline (dropped / replaced ones greyed) and
//  feedback (WhatsNewFeedback.swift) that goes back to Claude.
//
//  Source: shukr/WhatsNew.json (bundled) — `topics` + chronological `entries`, edited with
//  scripts/whatsnew.py (add / shot / resolve). Screenshots: shukr/WhatsNewShots/wn-*.jpg.
//  An entry committed with its change can't know its own hash, so it says "next"; `resolve`
//  fills in the hash and commit time before the following commit.
//

import SwiftUI
import StoreKit

struct WhatsNewTopic: Decodable {
    let id: String
    let area: String
    let title: String
    let tryIt: [String]?
    /// Where "Open in shukr" goes: salah / zikr / settings / history / azkar / map / names /
    /// ayah / insights (PrayerTimesView handles `WhatsNew.go`). Nil = nothing to open (widgets…).
    var link: String? = nil
}

struct WhatsNewEntry: Decodable, Identifiable {
    /// Stable ("<topic>-<n>"); older files had none, so the id falls back to commit | title.
    let entryID: String?
    let date: String          // "2026-09-27"
    let commit: String        // short hash, or "next"
    let time: String?         // ISO 8601 commit time (filled by `whatsnew.py resolve`)
    let topic: String
    let notes: String?        // the ideas notes item, "#17"
    let title: String
    let tryIt: [String]
    let checked: String       // "sim" | "phone" | "no"
    let status: String?       // "dropped" | "replaced" | "removed"
    let shots: [String]?
    var id: String { entryID ?? legacyID }
    /// v1's id (commit | title) — old tested ticks and NEW marks were keyed by it.
    var legacyID: String { "\(commit)|\(title)" }

    enum CodingKeys: String, CodingKey {
        case entryID = "id", date, commit, time, topic, notes, title, tryIt, checked, status, shots
    }

    /// Part of the build that's running.
    var inThisBuild: Bool { commit == "next" || commit == BuildInfo.commit }
    /// Replaced / dropped: shown greyed in the timeline, never the card's current state.
    var superseded: Bool { status == "dropped" || status == "replaced" }
    var date_: Date? { time.flatMap { WhatsNew.iso.date(from: $0) } }
}

/// One card: a topic and all its changes (oldest first).
struct WhatsNewCard: Identifiable {
    let topic: WhatsNewTopic
    let entries: [WhatsNewEntry]
    var id: String { topic.id }
    var title: String { topic.title }
    var area: String { topic.area }
    var latest: WhatsNewEntry { entries.last! }
    /// Committed changes' times; "next" (this build) counts as newest.
    var latestDate: Date? {
        if entries.contains(where: { $0.commit == "next" }) { return BuildInfo.builtAt ?? Date() }
        return entries.compactMap(\.date_).max()
    }
    var notes: [String] {
        var seen: [String] = []
        for n in entries.compactMap(\.notes) where !seen.contains(n) { seen.append(n) }
        return seen
    }
    /// For feedback: "75e7d7d (dropped)", "95b56cb", …
    var commits: [String] { entries.map { e in e.status.map { "\(e.commit) (\($0))" } ?? e.commit } }
    var tryIt: [String] { topic.tryIt ?? entries.last(where: { !$0.superseded })?.tryIt ?? latest.tryIt }
    /// Newest first; the thumbnail is the newest change's first screenshot.
    var shots: [String] { entries.reversed().flatMap { $0.shots ?? [] } }
    var thumbnail: String? { shots.first }
    var inThisBuild: Bool { entries.contains(where: \.inThisBuild) }
    var isNew: Bool { entries.contains { WhatsNew.newIDs.contains($0.id) } }
    /// A new change on a tested topic makes it untested again. Keyed by the latest change's
    /// stable id, so resolving "next" → its hash doesn't untick it.
    var testedKey: String { "topic:\(topic.id)@\(latest.id)" }
    /// Keys earlier builds used for the same tick.
    var olderTestedKeys: [String] { ["topic:\(topic.id)@\(latest.commit)", latest.legacyID] }
}

enum WhatsNew {
    /// One bad element never loses the rest: each topic / entry decodes on its own.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(T.self) }
    }
    private struct RawFile: Decodable { let topics: [Lossy<WhatsNewTopic>]?; let entries: [Lossy<WhatsNewEntry>]? }
    private struct File { let topics: [WhatsNewTopic]; let entries: [WhatsNewEntry] }

    private static let file: File = {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode(RawFile.self, from: data) else {
            print("⚠️ What's new: WhatsNew.json missing or unreadable")
            return File(topics: [], entries: [])
        }
        let topics = (raw.topics ?? []).compactMap(\.value)
        let entries = (raw.entries ?? []).compactMap(\.value)
        let skipped = (raw.topics?.count ?? 0) - topics.count + (raw.entries?.count ?? 0) - entries.count
        if skipped > 0 { print("⚠️ What's new: skipped \(skipped) unreadable topic(s) / entr(ies)") }
        return File(topics: topics, entries: entries)
    }()
    static var entries: [WhatsNewEntry] { file.entries }

    /// Newest change first.
    static let cards: [WhatsNewCard] = {
        let byTopic = Dictionary(grouping: file.entries, by: \.topic)
        var topics = Dictionary(file.topics.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // An entry whose topic is missing still shows: a stand-in topic from its latest entry.
        for (id, list) in byTopic where topics[id] == nil {
            topics[id] = WhatsNewTopic(id: id, area: "Other", title: list.last?.title ?? id, tryIt: nil, link: nil)
        }
        return byTopic.compactMap { id, list in topics[id].map { WhatsNewCard(topic: $0, entries: list) } }
            .sorted { ($0.latestDate ?? .distantPast) > ($1.latestDate ?? .distantPast) }
    }()
    static func card(id: String) -> WhatsNewCard? { cards.first { $0.id == id } }

    /// "Open in shukr": What's new closes and PrayerTimesView takes the user to `link`, so testing
    /// starts from the note (owner, 2026-09-27).
    static let go = Notification.Name("whatsNewGo")

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// "today 4:07 AM" · "yesterday 9:12 PM" · "Sep 25, 4:07 AM".
    static func whenLabel(_ date: Date?) -> String {
        guard let date else { return "this build" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday \(time)" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    static func image(_ name: String) -> UIImage? {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    // MARK: NEW since the build you opened before this one

    private static let currentKey = "whatsNew.currentBuild"      // "<commit>|<yyyy-MM-dd>"
    private static let previousKey = "whatsNew.previousBuild"

    /// This build's identity; the first launch of a new build moves the old one to "previous".
    private static let previousBuild: (commit: String, date: String)? = {
        let d = UserDefaults.standard
        let day = BuildInfo.builtAt.map { PrayerNotificationID.dayKey($0) } ?? ""
        let current = "\(BuildInfo.stamp ?? "dev")|\(day)|\(BuildInfo.builtAt?.timeIntervalSince1970 ?? 0)"
        if d.string(forKey: currentKey) != current {
            if let old = d.string(forKey: currentKey) { d.set(old, forKey: previousKey) }
            d.set(current, forKey: currentKey)
        }
        guard let prev = d.string(forKey: previousKey) else { return nil }
        let parts = prev.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let commit = parts[0].hasSuffix("+") ? String(parts[0].dropLast()) : parts[0]
        return (commit, parts[1])
    }()

    /// Call once at launch so a new build is noticed even before the page is opened.
    static func noteLaunch() { _ = previousBuild }

    /// Entries added after the build you last had open.
    static let newIDs: Set<String> = {
        guard let prev = previousBuild else {
            // First time: this build's own entries.
            return Set(entries.filter(\.inThisBuild).map(\.id))
        }
        if let last = entries.lastIndex(where: { $0.commit == prev.commit }) {
            return Set(entries[(last + 1)...].map(\.id))
        }
        return Set(entries.filter { $0.date > prev.date }.map(\.id))
    }()

    // MARK: Tested ticks (per topic; v1's per-entry ticks still count for a topic's latest change)

    static let testedKey = "whatsNew.tested"
    static func tested() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: testedKey) ?? []) }
    static func isTested(_ card: WhatsNewCard, in set: Set<String> = tested()) -> Bool {
        set.contains(card.testedKey) || card.olderTestedKeys.contains(where: set.contains)
    }
    static func setTested(_ card: WhatsNewCard, _ on: Bool) {
        var set = tested()
        if on { set.insert(card.testedKey) } else { set.remove(card.testedKey); card.olderTestedKeys.forEach { set.remove($0) } }
        UserDefaults.standard.set(Array(set), forKey: testedKey)
    }
}

/// Whether this build may show the page: DEBUG always; otherwise only TestFlight (sandbox) builds.
@MainActor final class WhatsNewAccess: ObservableObject {
    static let shared = WhatsNewAccess()
    @Published private(set) var available: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private init() {
        #if !DEBUG
        Task { @MainActor in
            if case .verified(let transaction) = try? await AppTransaction.shared {
                available = transaction.environment != .production
            }
        }
        #endif
    }
}

/// The build line, tappable into "What's new" where it's allowed.
struct BuildLineButton: View {
    var action: () -> Void
    @ObservedObject private var access = WhatsNewAccess.shared
    var body: some View {
        if access.available {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(BuildInfo.line)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("What's new in this build")
        } else {
            Text(BuildInfo.line)
        }
    }
}

// MARK: - The page

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tested = WhatsNew.tested()
    @State private var feedback = FeedbackStore.shared
    @AppStorage("whatsNew.untestedOnly") private var untestedOnly = false
    @State private var path: [String] = []
    @State private var composing: (card: WhatsNewCard, kind: FeedbackItem.Kind)?
    @State private var sharing: [FeedbackItem]?
    /// Copied rather than sent somewhere: ask before marking them sent.
    @State private var askMarkSent: [FeedbackItem]?

    private var shown: [WhatsNewCard] {
        WhatsNew.cards.filter { !untestedOnly || !WhatsNew.isTested($0, in: tested) }
    }
    /// Days of the latest change, newest first.
    private var days: [(label: String, cards: [WhatsNewCard])] {
        var result: [(label: String, cards: [WhatsNewCard])] = []
        for card in shown {
            let label = dayLabel(card.latestDate)
            if result.last?.label != label { result.append((label, [])) }
            result[result.count - 1].cards.append(card)
        }
        return result
    }
    private var untestedCount: Int { WhatsNew.cards.filter { !WhatsNew.isTested($0, in: tested) }.count }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if shown.isEmpty {
                        Text(untestedOnly ? "Everything's ticked. Nice." : "Nothing here yet.")
                            .font(.subheadline).fontWeight(.light).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(days, id: \.label) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.label)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .tracking(1.4).textCase(.uppercase)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 4)
                            ForEach(day.cards) { card in
                                WhatsNewCardView(card: card, tested: WhatsNew.isTested(card, in: tested),
                                                 unsent: feedback.unsent(for: card.id),
                                                 anySent: feedback.all(for: card.id).contains { $0.sentAt != nil },
                                                 toggleTested: { toggle(card) },
                                                 giveFeedback: { composing = (card, $0) },
                                                 open: card.topic.link.map { link in { open(link) } })
                                    .contentShape(Rectangle())
                                    .onTapGesture { path.append(card.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .fontDesign(.rounded)
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            #if DEBUG
            .task {
                if let id = UserDefaults.standard.string(forKey: "demoWhatsNewTopic"), path.isEmpty { path = [id] }
            }
            #endif
            .navigationDestination(for: String.self) { id in
                if let card = WhatsNew.card(id: id) {
                    WhatsNewDetailView(card: card, tested: $tested,
                                       open: card.topic.link.map { link in { open(link) } })
                }
            }
        }
        .sheet(isPresented: Binding(get: { composing != nil }, set: { if !$0 { composing = nil } })) {
            if let c = composing {
                NavigationStack {
                    ScrollView {
                        FeedbackComposer(card: c.card, startKind: c.kind) { composing = nil }
                            .padding(16)
                    }
                    .navigationTitle(c.card.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { composing = nil } } }
                }
                .presentationDetents([.medium, .large])
                .fontDesign(.rounded)
            }
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let list = sharing {
                FeedbackShareSheet(items: feedback.shareFiles(for: list)) { done, activity in
                    sharing = nil
                    guard done else { return }
                    if activity == .copyToPasteboard {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askMarkSent = list }
                    } else {
                        feedback.markSent(Set(list.map(\.id)))
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Mark as sent?", isPresented: Binding(get: { askMarkSent != nil }, set: { if !$0 { askMarkSent = nil } })) {
            Button("Mark sent") { if let list = askMarkSent { feedback.markSent(Set(list.map(\.id))) }; askMarkSent = nil }
            Button("Not yet", role: .cancel) { askMarkSent = nil }
        } message: {
            Text("You copied it. Once it's pasted into Claude, mark it sent so it isn't sent again.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BuildInfo.line)
                .font(.footnote).foregroundStyle(.secondary)
            sendButton
            HStack {
                Text("\(untestedCount) untested")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    withAnimation(.snappy) { untestedOnly.toggle() }
                } label: {
                    Label("Untested only", systemImage: untestedOnly ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(untestedOnly ? Color.green : Color.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(untestedOnly ? Color.green.opacity(0.12) : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    /// Everything not yet sent, as one Markdown summary + photos through the share sheet.
    private var sendButton: some View {
        let unsent = feedback.unsentItems
        return Button {
            sharing = unsent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                Text(unsent.isEmpty ? "No feedback to send" : "Send feedback")
                    .fontWeight(.semibold)
                Spacer()
                if !unsent.isEmpty {
                    Text("\(unsent.count) unsent")
                        .font(.subheadline)
                        .foregroundStyle(Color.green.opacity(0.8))
                }
            }
            .foregroundStyle(unsent.isEmpty ? Color.secondary : Color.green)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(unsent.isEmpty ? Color(.tertiarySystemFill) : Color.green.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(unsent.isEmpty)
    }

    private func open(_ link: String) {
        dismiss()
        NotificationCenter.default.post(name: WhatsNew.go, object: link)
    }

    private func toggle(_ card: WhatsNewCard) {
        let now = !WhatsNew.isTested(card, in: tested)
        WhatsNew.setTested(card, now)
        withAnimation(.snappy) { tested = WhatsNew.tested() }
    }

    private func dayLabel(_ date: Date?) -> String {
        guard let d = date else { return "This build" }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - A card

/// At a glance: area · title · latest change · N changes · thumbnail · tested; feedback buttons.
struct WhatsNewCardView: View {
    let card: WhatsNewCard
    let tested: Bool
    let unsent: FeedbackItem?
    let anySent: Bool
    let toggleTested: () -> Void
    let giveFeedback: (FeedbackItem.Kind) -> Void
    /// "Open in shukr" (nil when the feature has no page to open).
    var open: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let name = card.thumbnail, let ui = WhatsNew.image(name) {
                Image(uiImage: ui)
                    .resizable().scaledToFill()
                    .frame(width: 46, height: 66, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(card.area)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .tracking(1).textCase(.uppercase)
                        .foregroundStyle(Color.sage)
                    if !card.notes.isEmpty {
                        Text(card.notes.joined(separator: " "))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    if card.isNew {
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green))
                    }
                }
                Text(card.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(tested ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Text(WhatsNew.whenLabel(card.latestDate))
                    if card.entries.count > 1 { Text("· \(card.entries.count) changes") }
                    if card.inThisBuild { Text("· this build").foregroundStyle(Color.green) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                feedbackRow
                    .padding(.top, 2)
            }
            Spacer(minLength: 4)
            Button(action: toggleTested) {
                Image(systemName: tested ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(tested ? Color.green : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: tested)
            .accessibilityLabel(tested ? "Tested" : "Mark tested")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(card.inThisBuild ? Color.green.opacity(0.3) : .clear, lineWidth: 1))
    }

    private var feedbackRow: some View {
        HStack(spacing: 16) {
            ForEach(FeedbackItem.Kind.allCases, id: \.self) { kind in
                let on = unsent?.kind == kind
                Button { giveFeedback(kind) } label: {
                    Image(systemName: on ? kind.symbol : kind.symbol.replacingOccurrences(of: ".fill", with: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(on ? kind.color : Color(.tertiaryLabel))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.label)
            }
            if let open {
                Button(action: open) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.sage)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open in shukr")
            }
            if unsent != nil {
                Text(unsent?.photo != nil ? "unsent · photo" : "unsent")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.orange)
            } else if anySent {
                Text("sent")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Detail

struct WhatsNewDetailView: View {
    let card: WhatsNewCard
    @Binding var tested: Set<String>
    var open: (() -> Void)? = nil
    @State private var feedback = FeedbackStore.shared
    @State private var viewing: UIImage?

    private var isTested: Bool { WhatsNew.isTested(card, in: tested) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section("Try it") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(card.tryIt.enumerated()), id: \.offset) { n, step in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(n + 1).").monospacedDigit().foregroundStyle(.tertiary)
                                Text(step)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                if !card.shots.isEmpty {
                    section("Screenshots") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(card.shots, id: \.self) { name in
                                    if let ui = WhatsNew.image(name) {
                                        Image(uiImage: ui)
                                            .resizable().scaledToFit()
                                            .frame(height: 380)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                                            .onTapGesture { viewing = ui }
                                    }
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
                }
                section("Feedback") {
                    VStack(alignment: .leading, spacing: 14) {
                        FeedbackComposer(card: card)
                        let sent = feedback.all(for: card.id).filter { $0.sentAt != nil }.reversed()
                        ForEach(Array(sent)) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color.opacity(0.7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text.isEmpty ? item.kind.label : item.text)
                                    Text("sent \(item.sentAt!.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                section("Changes") { timeline }
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle(card.area)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { viewing.map(IdentifiedImage.init) }, set: { viewing = $0?.image })) {
            ZikrPhotoViewer(image: $0.image)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(card.area)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .tracking(1).textCase(.uppercase)
                    .foregroundStyle(Color.sage)
                if !card.notes.isEmpty {
                    Text("notes \(card.notes.joined(separator: " "))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(card.title)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(WhatsNew.whenLabel(card.latestDate)) · \(card.entries.count == 1 ? "1 change" : "\(card.entries.count) changes")")
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                WhatsNew.setTested(card, !isTested)
                withAnimation(.snappy) { tested = WhatsNew.tested() }
            } label: {
                Label(isTested ? "Tested" : "Mark tested", systemImage: isTested ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isTested ? Color.green : Color.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(isTested ? Color.green.opacity(0.12) : Color(.tertiarySystemFill)))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isTested)
            .padding(.top, 2)
            if let open {
                Button(action: open) {
                    Label("Open in shukr", systemImage: "arrow.up.forward.app")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.sage)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Color.sage.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Newest first: time · commit · one line; dropped / replaced greyed with the word.
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            let list = Array(card.entries.reversed())
            ForEach(Array(list.enumerated()), id: \.element.id) { i, entry in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(entry.superseded ? Color(.tertiaryLabel) : (i == 0 ? Color.green : Color.sage))
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                        if i < list.count - 1 {
                            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(entry.date_.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) } ?? "this build")
                            Text(entry.commit == "next" ? (BuildInfo.commit ?? "next") : entry.commit)
                                .font(.system(size: 11, design: .monospaced))
                            if entry.inThisBuild { Text("this build").foregroundStyle(Color.green) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(entry.superseded || entry.status == "removed" ? "\(entry.title): \(entry.status!)" : entry.title)
                            .font(.subheadline)
                            .foregroundStyle(entry.superseded ? .tertiary : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(1.4).textCase(.uppercase)
                .foregroundStyle(.tertiary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
    }
}

private struct IdentifiedImage: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}
