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
//  v3 (2026-09-27, notes #23): the page shows only what needs the owner — "To check" (notes a
//  change addressed: `addresses` on an entry), "To test" (untested, not hidden), "Unsent notes" —
//  and everything else in a collapsed, searchable Archive. Any card can be hidden (back when a
//  newer change lands on its topic, or its note is addressed). Each change carries its own
//  screenshots, shown with it in the detail's timeline. "Open in shukr" pushes pages inside the
//  sheet (‹ Back returns to the card); the pager pages and the map close it and leave a
//  "‹ What's new" pill (`WhatsNewReturn`) that reopens it at the same card.
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
    /// Feedback ids (UUIDs, or an 8+ character prefix) this change fixes.
    let addresses: [String]?
    var id: String { entryID ?? legacyID }
    /// v1's id (commit | title) — old tested ticks and NEW marks were keyed by it.
    var legacyID: String { "\(commit)|\(title)" }

    enum CodingKeys: String, CodingKey {
        case entryID = "id", date, commit, time, topic, notes, title, tryIt, checked, status, shots, addresses
    }

    /// "this build" or the short hash — what "Addressed in …" names.
    var buildLabel: String { inThisBuild ? "this build" : commit }

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
    /// The newest live change's picture (a dropped / replaced change's screenshot shows the old look).
    var thumbnail: String? { entries.reversed().first { !$0.superseded && !($0.shots ?? []).isEmpty }?.shots?.first }
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

    /// The newest change that lists this feedback id in `addresses`.
    /// Cached per id: the entries are fixed for the build, and every note's state asks this.
    @MainActor static func addressing(_ id: UUID) -> WhatsNewEntry? {
        if let hit = addressingCache[id] { return hit }
        let full = id.uuidString.lowercased()
        let found = entries.last { e in
            !e.superseded && (e.addresses ?? []).contains { a in a.count >= 8 && full.hasPrefix(a.lowercased()) }
        }
        addressingCache[id] = .some(found)
        return found
    }
    @MainActor private static var addressingCache: [UUID: WhatsNewEntry?] = [:]

    // MARK: Hidden cards (by hand): topic → the latest change's id when it was hidden

    private static let hiddenKey = "whatsNew.hidden"
    static func hidden() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: hiddenKey) as? [String: String] ?? [:]
    }
    /// Still hidden only while no newer change has landed on the topic.
    static func isHidden(_ card: WhatsNewCard, in map: [String: String] = hidden()) -> Bool {
        map[card.id] == card.latest.id
    }
    static func setHidden(_ card: WhatsNewCard, _ on: Bool) {
        var map = hidden()
        map[card.id] = on ? card.latest.id : nil
        UserDefaults.standard.set(map, forKey: hiddenKey)
    }

    /// Pages "Open in shukr" can push inside the What's new sheet (‹ Back returns to the card).
    static let pushable: Set<String> = ["history", "azkar", "names", "ayah", "insights"]

    /// "Open in shukr": What's new closes and PrayerTimesView takes the user to `link`, so testing
    /// starts from the note (owner, 2026-09-27).
    static let go = Notification.Name("whatsNewGo")
    /// The pages "Open in shukr" can go to (PrayerTimesView's `WhatsNew.go` handler); a topic with
    /// any other link shows no button.
    static let links: Set<String> = ["salah", "zikr", "settings", "history", "azkar", "map", "names", "ayah", "insights"]

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

/// After "Open in shukr" closed the sheet (a pager page, the map): the card to reopen it at, shown as
/// a small "‹ What's new" pill (PrayerTimesView).
@MainActor @Observable final class WhatsNewReturn {
    static let shared = WhatsNewReturn()
    var card: String?
}

/// The "‹ What's new" pill after "Open in shukr" left the sheet: tap → What's new again, on the
/// same card; ✕ → gone. On the root page and the map (a full-screen cover hides the root's).
struct WhatsNewReturnPill: ViewModifier {
    @State private var ret = WhatsNewReturn.shared
    @State private var reopen: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                if let card = ret.card {
                    HStack(spacing: 0) {
                        Button {
                            triggerSomeVibration(type: .light)
                            reopen = card
                            ret.card = nil
                        } label: {
                            Label("What's new", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
                        }
                        Button {
                            withAnimation(.snappy) { ret.card = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 14).padding(.leading, 4).padding(.vertical, 10)
                        }
                        .accessibilityLabel("Dismiss")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.sage)
                    .mapGlass(Capsule())
                    .padding(.leading, 16)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: ret.card)
            .sheet(item: Binding(get: { reopen.map(ReturnCard.init) }, set: { reopen = $0?.id })) { c in
                WhatsNewView(startCard: c.id)
            }
    }

    private struct ReturnCard: Identifiable { let id: String }
}

extension View {
    func whatsNewReturnPill() -> some View { modifier(WhatsNewReturnPill()) }
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

enum WhatsNewRoute: Hashable {
    case card(String)
    /// A page pushed inside the sheet ("Open in shukr" for a pushable link).
    case page(String)
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tested = WhatsNew.tested()
    @State private var hidden = WhatsNew.hidden()
    @State private var feedback = FeedbackStore.shared
    @State private var path: [WhatsNewRoute]
    @State private var composing: (card: WhatsNewCard, kind: FeedbackItem.Kind, followUp: UUID?)?
    @State private var sharing: [FeedbackItem]?
    /// Copied rather than sent somewhere: ask before marking them sent.
    @State private var askMarkSent: [FeedbackItem]?
    @State private var archiveOpen = false
    @State private var archiveSearch = ""

    /// `startCard`: open on that card's detail (the "‹ What's new" pill).
    init(startCard: String? = nil) {
        _path = State(initialValue: startCard.map { [.card($0)] } ?? [])
    }

    // MARK: What needs you

    /// A card is done once it's ticked tested, or a note on it was closed after its latest change.
    private func isDone(_ card: WhatsNewCard) -> Bool {
        if WhatsNew.isTested(card, in: tested) { return true }
        let since = card.latestDate ?? .distantPast
        return feedback.all(for: card.id).contains { item in
            guard case .closed = feedback.state(item) else { return false }
            return (item.closedAt ?? item.updated) >= since
        }
    }
    private var checkTopics: Set<String> { Set(feedback.toCheck.map(\.item.topic)) }
    private var toTest: [WhatsNewCard] {
        WhatsNew.cards.filter { !isDone($0) && !WhatsNew.isHidden($0, in: hidden) && !checkTopics.contains($0.id) }
    }
    private var unsentCards: [WhatsNewCard] {
        let shown = Set(toTest.map(\.id)).union(checkTopics)
        return WhatsNew.cards.filter { feedback.unsent(for: $0.id) != nil && !shown.contains($0.id) }
    }
    /// Tested, closed or hidden — everything not shown above (a topic waiting in "To check" is up there).
    private var archivedCards: [WhatsNewCard] {
        let shown = Set(toTest.map(\.id)).union(unsentCards.map(\.id)).union(checkTopics)
        return WhatsNew.cards.filter { !shown.contains($0.id) }
    }
    private var archive: [WhatsNewCard] {
        let q = archiveSearch.trimmingCharacters(in: .whitespaces)
        return archivedCards.filter { card in
            guard !q.isEmpty else { return true }
            return card.title.localizedCaseInsensitiveContains(q) || card.area.localizedCaseInsensitiveContains(q)
                || card.entries.contains { $0.title.localizedCaseInsensitiveContains(q) }
                || feedback.all(for: card.id).contains { $0.text.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    let checks = feedback.toCheck
                    if !checks.isEmpty {
                        section("To check", count: checks.count) {
                            ForEach(checks, id: \.item.id) { check in
                                FeedbackCheckCard(item: check.item, fix: check.fix,
                                                  looksGood: { withAnimation(.snappy) { feedback.close(check.item) } },
                                                  stillOff: { stillOff(check.item) })
                                    .contentShape(Rectangle())
                                    .onTapGesture { path.append(.card(check.item.topic)) }
                            }
                        }
                    }
                    if !toTest.isEmpty {
                        section("To test", count: toTest.count) { ForEach(toTest) { cardView($0) } }
                    }
                    if !unsentCards.isEmpty {
                        section("Unsent notes", count: unsentCards.count) { ForEach(unsentCards) { cardView($0) } }
                    }
                    if checks.isEmpty && toTest.isEmpty && unsentCards.isEmpty {
                        Text("Nothing needs you. Everything's tested or closed.")
                            .font(.subheadline).fontWeight(.light).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    archiveSection
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
                if let id = UserDefaults.standard.string(forKey: "demoWhatsNewTopic"), path.isEmpty { path = [.card(id)] }
                if UserDefaults.standard.bool(forKey: "demoWhatsNewArchive") { archiveOpen = true }
            }
            #endif
            .navigationDestination(for: WhatsNewRoute.self) { route in
                switch route {
                case .card(let id):
                    if let card = WhatsNew.card(id: id) {
                        WhatsNewDetailView(card: card, tested: $tested, open: opener(for: card),
                                           stillOff: stillOff)
                    }
                case .page(let link):
                    pushedPage(link)
                }
            }
        }
        .onAppear {
            feedback.reloadReceived()
            WhatsNewReturn.shared.card = nil      // opened (any way): the "‹ What's new" pill has done its job
        }
        .sheet(isPresented: Binding(get: { composing != nil }, set: { if !$0 { closeComposer() } })) {
            if let c = composing {
                NavigationStack {
                    ScrollView {
                        FeedbackComposer(card: c.card, startKind: c.kind, followUpOf: c.followUp) { composing = nil }
                            .padding(16)
                    }
                    .navigationTitle(c.followUp == nil ? c.card.title : "Still off: what's wrong?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { closeComposer() } } }
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

    private func cardView(_ card: WhatsNewCard, archived: Bool = false) -> some View {
        let isHidden = WhatsNew.isHidden(card, in: hidden)
        return WhatsNewCardView(card: card, tested: WhatsNew.isTested(card, in: tested),
                                status: statusText(card), hidden: isHidden,
                                unsent: feedback.unsent(for: card.id),
                                toggleTested: { toggle(card) },
                                giveFeedback: { composing = (card, $0, nil) },
                                open: opener(for: card))
            .opacity(archived ? 0.75 : 1)
            .contentShape(Rectangle())
            .onTapGesture { path.append(.card(card.id)) }
            .contextMenu {
                Button(isHidden ? "Show again" : "Hide", systemImage: isHidden ? "eye" : "eye.slash") {
                    WhatsNew.setHidden(card, !isHidden)
                    withAnimation(.snappy) { hidden = WhatsNew.hidden() }
                }
            }
    }

    /// The card's newest note, as a word: received / sent / addressed / closed.
    private func statusText(_ card: WhatsNewCard) -> String? {
        guard let item = feedback.all(for: card.id).last(where: { if case .draft = feedback.state($0) { false } else { true } }) else { return nil }
        switch feedback.state(item) {
        case .received(let d):
            return "received " + (Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : WhatsNew.whenLabel(d))
        case .sent: return "sent"
        case .toCheck: return "addressed · check it"
        case .closed: return item.kind == .works ? "👍 works" : "closed"
        case .reopened: return "still off"
        case .draft: return nil
        }
    }

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { archiveOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Archive")
                    Text("\(archivedCards.count)").foregroundStyle(.quaternary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(archiveOpen ? 0 : -90))
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(1.4).textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if archiveOpen {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Search the archive", text: $archiveSearch)
                }
                .font(.subheadline)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                ForEach(archive) { cardView($0, archived: true) }
                if archive.isEmpty {
                    Text(archiveSearch.isEmpty ? "Nothing archived yet." : "Nothing matches.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)").foregroundStyle(.quaternary)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .tracking(1.4).textCase(.uppercase)
            .foregroundStyle(.tertiary)
            .padding(.leading, 4)
            content()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BuildInfo.line)
                .font(.footnote).foregroundStyle(.secondary)
            sendButton
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

    /// Cancel / swipe away: a "Still off" with nothing written goes back to "to check".
    private func closeComposer() {
        if let id = composing?.followUp { feedback.undoReopen(id) }
        composing = nil
    }

    /// "Still off": the note reopens and a follow-up note starts on its topic.
    private func stillOff(_ item: FeedbackItem) {
        feedback.reopen(item)
        if let card = WhatsNew.card(id: item.topic) { composing = (card, .issue, item.id) }
    }

    // MARK: Open in shukr

    private func opener(for card: WhatsNewCard) -> (() -> Void)? {
        guard let link = card.topic.link, WhatsNew.links.contains(link) else { return nil }
        return { open(link, from: card) }
    }

    private func open(_ link: String, from card: WhatsNewCard) {
        if WhatsNew.pushable.contains(link) {
            path.append(.page(link))                 // ‹ Back returns to the card
            return
        }
        WhatsNewReturn.shared.card = card.id         // the pill reopens it here
        dismiss()
        NotificationCenter.default.post(name: WhatsNew.go, object: link)
    }

    @ViewBuilder private func pushedPage(_ link: String) -> some View {
        switch link {
        case "history": ZikrLibraryView(start: .history)
        case "azkar": ZikrLibraryView(start: .mantras)
        case "names": NamesOfAllahView()
        case "ayah": DailyAyahView()
        case "insights": InsightsView()
        default: EmptyView()
        }
    }

    private func toggle(_ card: WhatsNewCard) {
        let now = !WhatsNew.isTested(card, in: tested)
        WhatsNew.setTested(card, now)
        withAnimation(.snappy) { tested = WhatsNew.tested() }
    }
}

/// A note a change addressed: the note, what fixed it, Looks good ✓ / Still off.
struct FeedbackCheckCard: View {
    let item: FeedbackItem
    let fix: WhatsNewEntry
    /// On the card's own page the note is already shown above: just the fix and the buttons.
    var compact = false
    let looksGood: () -> Void
    let stillOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact { noteHeader }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.green)
                (Text("Addressed in \(fix.buildLabel): ").fontWeight(.semibold) + Text(fix.title))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
            buttons
        }
        .padding(compact ? 12 : 14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.green.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder private var noteHeader: some View {
            HStack(spacing: 6) {
                Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color.opacity(0.7))
                Text(WhatsNew.card(id: item.topic)?.area ?? item.topic)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .tracking(1).textCase(.uppercase)
                    .foregroundStyle(Color.sage)
                Spacer()
                Text("you, \(item.updated.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Text(WhatsNew.card(id: item.topic)?.title ?? item.topicTitle)   // which feature
                .font(.footnote.weight(.medium))
                .lineLimit(2)
            Text(item.text.isEmpty ? item.kind.label : "“\(item.text)”")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
    }

    private var buttons: some View {
            HStack(spacing: 10) {
                Button(action: looksGood) {
                    Label("Looks good", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.green.opacity(0.14)))
                }
                Button(action: stillOff) {
                    Text("Still off")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: item.closedAt)
    }
}

// MARK: - A card

/// At a glance: area · title · latest change · N changes · thumbnail · tested; feedback buttons.
struct WhatsNewCardView: View {
    let card: WhatsNewCard
    let tested: Bool
    /// The newest sent note's state ("received 4:36 PM", "addressed · check it", …).
    var status: String? = nil
    var hidden = false
    let unsent: FeedbackItem?
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
                    if hidden {
                        Image(systemName: "eye.slash").font(.system(size: 10)).foregroundStyle(.tertiary)
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
            } else if let status {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Detail

struct WhatsNewDetailView: View {
    let card: WhatsNewCard
    @Binding var tested: Set<String>
    var open: (() -> Void)? = nil
    var stillOff: (FeedbackItem) -> Void = { _ in }
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
                section("Feedback") {
                    VStack(alignment: .leading, spacing: 14) {
                        // Earlier notes, greyed with where they stand; the box under them is for
                        // new feedback (a received note isn't edited again).
                        // Everything but the box's own draft (a "Still off" follow-up draft lists here
                        // as "Not sent yet"; its own composer edits it).
                        let past = feedback.all(for: card.id).filter { feedback.draft(for: card.id)?.id != $0.id }
                        ForEach(past) { item in pastNote(item) }
                        if !past.isEmpty { Divider() }
                        FeedbackComposer(card: card)
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

    @ViewBuilder private func pastNote(_ item: FeedbackItem) -> some View {
        let state = feedback.state(item)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color.opacity(0.6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.text.isEmpty ? item.kind.label : item.text)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stateLine(item, state))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if let ui = feedback.image(for: item) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(0.8)
                        .onTapGesture { viewing = ui }
                }
            }
            if case .toCheck(let fix) = state {
                FeedbackCheckCard(item: item, fix: fix, compact: true,
                                  looksGood: { withAnimation(.snappy) { feedback.close(item) } },
                                  stillOff: { stillOff(item) })
            }
        }
        .font(.subheadline)
    }

    private func stateLine(_ item: FeedbackItem, _ state: FeedbackState) -> String {
        let t = { (d: Date) in WhatsNew.whenLabel(d) }
        switch state {
        case .received(let d): return "Received by Claude · \(t(d))"
        case .sent(let d): return "Sent \(t(d))"
        case .toCheck(let fix): return "Addressed in \(fix.buildLabel)"
        case .closed:
            if let c = item.closedAt { return "Looks good · \(t(c))" }
            return feedback.received[item.id].map { "Received by Claude · \(t($0)) · closed" } ?? "Sent · closed"
        case .reopened: return "Still off · \(item.reopenedAt.map(t) ?? "")"
        case .draft: return "Not sent yet"
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
                        // Each change with its own pictures (per change, not per topic).
                        if let shots = entry.shots, !shots.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(shots, id: \.self) { name in
                                        if let ui = WhatsNew.image(name) {
                                            Image(uiImage: ui)
                                                .resizable().scaledToFit()
                                                .frame(height: i == 0 ? 300 : 170)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                                                .opacity(entry.superseded ? 0.5 : 1)
                                                .onTapGesture { viewing = ui }
                                        }
                                    }
                                }
                            }
                            .scrollClipDisabled()
                            .padding(.top, 4)
                        }
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
