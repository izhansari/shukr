//
//  WhatsNew.swift
//  shukr
//
//  "What's new" v4 (2026-09-29, Ben) — the owner's inbox for the builds he tests. Tap the build line
//  (bottom of the ☰ menu and of Settings). DEBUG builds always; a TestFlight install only once it's
//  unlocked on his phone (hold the build line 3 s) — testers never see it; App Store builds never.
//
//  The page (WhatsNewPage.swift): Your answers (what he's said, until the team has read it) · Your asks
//  (things he asked for that were built: Works / Not yet) · Every change (the log, by day, searchable).
//
//  Source: shukr/WhatsNew.jsonl (bundled), JSON Lines written only by scripts/whatsnew.py:
//  topics (features), asks (his requests, verbatim), changes (one per visible change) and chat verdicts
//  (answers he gave in chat, recorded by Bradley). Screenshots: shukr/WhatsNewShots/wn-*.jpg.
//
//  ONE rule decides an ask's state (`status(of:)`): it's open until there's an answer on its newest live
//  change — his Works / Not yet on the phone, a verdict from chat, or (once) what v3 had already closed.
//  A newer change on the same ask opens it again.
//

import SwiftUI
import StoreKit

// MARK: - The records

struct WhatsNewTopic: Decodable {
    let id: String
    let area: String
    /// Short (≤ 60 chars, "Prayers widget").
    let title: String
    /// The feature as it is now, in full.
    var summary: String? = nil
    var tryIt: [String]? = nil
    /// Where "Open in shukr" goes (`WhatsNew.links`); nil = nothing to open (widgets…).
    var link: String? = nil
}

/// Something the owner asked for: in chat (his words, relayed by Bradley) or in a note on the phone.
struct WhatsNewAsk: Decodable, Identifiable {
    let id: String
    let topic: String
    let source: String?         // "chat" | "note"
    let note: String?           // the feedback note's id (or a prefix of it)
    let created: String?
    let words: String?
    var fromNote: Bool { source == "note" }
}

/// One visible change.
struct WhatsNewEntry: Decodable, Identifiable {
    let id: String
    let time: String?
    let topic: String
    let asks: [String]?
    let notes: String?          // the ideas-notes item, "#17"
    let status: String?         // "dropped" | "replaced" | "removed"
    let checked: String?
    let commit: String?         // only on changes from before v4
    let headline: String?
    let title: String
    let tryIt: [String]?
    let shots: [String]?

    /// The headline, else the full title (older changes).
    var short: String { headline ?? title }
    var steps: [String] { tryIt ?? [] }
    var superseded: Bool { status == "dropped" || status == "replaced" }
    /// Still part of the feature.
    var live: Bool { !superseded && status != "removed" }
    var when: Date { time.flatMap(WhatsNew.date(from:)) ?? .distantPast }
    var askIDs: [String] { asks ?? [] }
}

/// An answer he gave in chat (whatsnew.py verdict / Bradley's queue).
struct WhatsNewChatVerdict: Decodable {
    let ask: String
    let verdict: String         // "works" | "notyet"
    let at: String
    let words: String?
    var works: Bool { verdict == "works" }
    var date: Date { WhatsNew.date(from: at) ?? .distantPast }
}

/// A TestFlight upload (whatsnew.py build, written by testflight.sh): "Next build" counts from the newest.
struct WhatsNewBuild: Decodable {
    let number: Int
    let time: String
    let commit: String
    var date: Date { WhatsNew.date(from: time) ?? .distantPast }
}

/// Where an ask stands.
enum AskStatus {
    /// Built and waiting for him: the newest live change is `latest`.
    case open(latest: WhatsNewEntry)
    /// He answered the newest change.
    case answered(works: Bool, latest: WhatsNewEntry, answer: AskAnswer)
    /// No live change (only dropped / replaced ones): nothing to check.
    case gone

    var isOpen: Bool { if case .open = self { true } else { false } }
}

/// Who answered and how.
struct AskAnswer {
    enum Source { case phone(FeedbackItem), chat(WhatsNewChatVerdict), earlier(String?) }
    let works: Bool
    let at: Date
    let source: Source
    var label: String {
        switch source {
        case .phone: works ? "You said it works" : "You said not yet"
        case .chat: works ? "You said it works (in chat)" : "You said not yet (in chat)"
        case .earlier(let how):
            how == "followed up" ? "Followed up in a later note" : works ? "Checked before" : "You said still off"
        }
    }
}

// MARK: - The file

enum WhatsNew {
    private struct Probe: Decodable { let kind: String? }
    private struct File {
        var topics: [String: WhatsNewTopic] = [:]
        var asks: [String: WhatsNewAsk] = [:]
        var entries: [WhatsNewEntry] = []
        var verdicts: [WhatsNewChatVerdict] = []
        var builds: [WhatsNewBuild] = []
    }

    /// Line by line: a bad line is skipped (and logged), never the file. A repeated id (a union merge
    /// can keep two versions of a line): the later line wins.
    private static let file: File = {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "jsonl"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            print("⚠️ What's new: WhatsNew.jsonl missing")
            return File()
        }
        var f = File(), bad = 0
        var entries: [String: WhatsNewEntry] = [:]
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let data = Data(line.utf8)
            switch (try? decoder.decode(Probe.self, from: data))?.kind {
            case "topic": if let t = try? decoder.decode(WhatsNewTopic.self, from: data) { f.topics[t.id] = t } else { bad += 1 }
            case "ask": if let a = try? decoder.decode(WhatsNewAsk.self, from: data) { f.asks[a.id] = a } else { bad += 1 }
            case "change": if let e = try? decoder.decode(WhatsNewEntry.self, from: data) { entries[e.id] = e } else { bad += 1 }
            case "verdict": if let v = try? decoder.decode(WhatsNewChatVerdict.self, from: data) { f.verdicts.append(v) } else { bad += 1 }
            case "build": if let b = try? decoder.decode(WhatsNewBuild.self, from: data) { f.builds.append(b) } else { bad += 1 }
            default: bad += 1
            }
        }
        f.entries = entries.values.sorted { $0.when < $1.when }
        if bad > 0 { print("⚠️ What's new: skipped \(bad) unreadable line(s)") }
        return f
    }()

    /// Every change, oldest first.
    static var entries: [WhatsNewEntry] { file.entries }
    /// The newest TestFlight upload on record (ask wn-next-build).
    static var lastBuild: WhatsNewBuild? { file.builds.max { ($0.date, $0.number) < ($1.date, $1.number) } }
    /// "Next build": every live change after the last upload, oldest first.
    static var sinceLastBuild: [WhatsNewEntry] {
        let after = lastBuild?.date ?? .distantPast
        return entries.filter { $0.live && $0.when > after }
    }
    static var asks: [WhatsNewAsk] { Array(file.asks.values) }
    static func ask(_ id: String) -> WhatsNewAsk? { file.asks[id] }
    static func topic(_ id: String) -> WhatsNewTopic? { file.topics[id] }
    static func entry(_ id: String) -> WhatsNewEntry? { entryIndex[id] }
    private static let entryIndex: [String: WhatsNewEntry] = Dictionary(file.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
    static func topicTitle(_ id: String) -> String { topic(id)?.title ?? id }
    static func area(_ id: String) -> String { topic(id)?.area ?? "Other" }
    /// The page's areas, in order — Your asks is grouped by them, Every change filters by them (owner,
    /// ask wn-areas). `scripts/whatsnew.py`'s AREAS keeps the same list; an unknown area sorts last.
    static let areaOrder = ["Salah", "Zikr", "Apple Watch", "Widgets", "Map & Mosques", "Insights", "Daily Ayah",
                            "99 Names", "Reminders", "Setup & Settings"]
    static func areaRank(_ area: String) -> Int { areaOrder.firstIndex(of: area) ?? areaOrder.count }
    /// A topic's changes, oldest first.
    static func entries(topic: String) -> [WhatsNewEntry] { byTopic[topic] ?? [] }
    private static let byTopic: [String: [WhatsNewEntry]] = Dictionary(grouping: file.entries, by: \.topic)
    /// An ask's live changes, oldest first.
    static func entries(ask: String) -> [WhatsNewEntry] { byAsk[ask] ?? [] }
    private static let byAsk: [String: [WhatsNewEntry]] = {
        var map: [String: [WhatsNewEntry]] = [:]
        for e in file.entries where e.live { for a in e.askIDs { map[a, default: []].append(e) } }
        return map
    }()

    // MARK: The one rule

    /// Open until there's an answer on its newest live change (a newer change opens it again).
    @MainActor static func status(of ask: WhatsNewAsk) -> AskStatus {
        guard let latest = entries(ask: ask.id).last else { return .gone }
        var best: AskAnswer?
        func consider(_ a: AskAnswer) { if best == nil || a.at > best!.at { best = a } }
        for item in FeedbackStore.shared.items where item.ask == ask.id && item.kind.isVerdict {
            // An answer counts for the change it was given on; one without (never, but safe) by time.
            if item.onEntry == latest.id || (item.onEntry == nil && item.created >= latest.when) {
                consider(AskAnswer(works: item.kind == .works, at: item.updated, source: .phone(item)))
            }
        }
        for v in file.verdicts where v.ask == ask.id && v.date >= latest.when {
            consider(AskAnswer(works: v.works, at: v.date, source: .chat(v)))
        }
        if let m = Migration.answers[ask.id], m.entry == latest.id {
            consider(AskAnswer(works: m.works, at: .distantPast, source: .earlier(m.how)))
        }
        guard let best else { return .open(latest: latest) }
        return .answered(works: best.works, latest: latest, answer: best)
    }

    /// Waiting for him, newest change first.
    @MainActor static func openAsks() -> [(ask: WhatsNewAsk, latest: WhatsNewEntry)] {
        #if DEBUG
        // `-demoWhatsNewAllOpen`: every ask listed as waiting (screenshots of Your asks by area). View-level
        // only: nothing about an ask's stored state changes.
        if ProcessInfo.processInfo.arguments.contains("-demoWhatsNewAllOpen") {
            return asks.compactMap { a in entries(ask: a.id).last.map { (a, $0) } }.sorted { $0.1.when > $1.1.when }
        }
        #endif
        return asks.compactMap { a in if case .open(let l) = status(of: a) { (a, l) } else { nil } }
            .sorted { $0.latest.when > $1.latest.when }
    }

    /// What he's said about this change (a Works / Not yet on it, or a comment), newest first.
    @MainActor static func said(on entry: WhatsNewEntry) -> [FeedbackItem] {
        FeedbackStore.shared.items.filter { $0.onEntry == entry.id }.sorted { $0.updated > $1.updated }
    }

    /// The small tag in the change list: "you said it works", "you said not yet", "you asked".
    @MainActor static func tag(for entry: WhatsNewEntry) -> (text: String, tone: Color)? {
        if let v = said(on: entry).first(where: { $0.kind.isVerdict }) {
            return v.kind == .works ? ("you said it works", .green) : ("you said not yet", .orange)
        }
        for id in entry.askIDs {
            if let a = ask(id), case .answered(let works, let latest, let answer) = status(of: a), latest.id == entry.id {
                if case .earlier(let how) = answer.source {
                    return (how == "followed up" ? "followed up" : works ? "checked" : "you said still off", Color(.secondaryLabel))
                }
                return works ? ("you said it works", .green) : ("you said not yet", .orange)
            }
        }
        return entry.askIDs.isEmpty ? nil : ("you asked", .sage)
    }

    // MARK: State for the team (Library/Feedback/state.json, copied by pull-feedback.sh)

    /// `{"asks": {slug: "open" | "works" | "notyet"}, "updated": …}` — which asks are still waiting for him.
    /// Written at launch and after every answer, only when it changed.
    @MainActor static func writeState() {
        guard WhatsNewAccess.shared.available else { return }
        guard let dir = FeedbackStore.folder else { return }
        var map: [String: String] = [:]
        for a in asks {
            switch status(of: a) {
            case .open: map[a.id] = "open"
            case .answered(let works, _, let answer):
                if case .earlier(let how) = answer.source, how == "followed up" { map[a.id] = "followed-up" }
                else { map[a.id] = works ? "works" : "notyet" }
            case .gone: break
            }
        }
        let body: [String: Any] = ["version": 4, "asks": map]
        guard let content = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        let url = dir.appendingPathComponent("state.json")
        if let old = try? Data(contentsOf: url), var obj = try? JSONSerialization.jsonObject(with: old) as? [String: Any] {
            obj["updated"] = nil
            if let o = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), o == content { return }
        }
        var withTime = body
        withTime["updated"] = iso.string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: withTime, options: [.sortedKeys, .prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// At launch: carry v3's state across once, and write the team's state file.
    @MainActor static func noteLaunch() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-whatsNewResetMigration") { Migration.resetForDebug() }
        #endif
        Migration.runOnce()
        writeState()
    }

    // MARK: Open in shukr

    /// Pages "Open in shukr" pushes inside the sheet (‹ Back returns).
    static let pushable: Set<String> = ["history", "azkar", "names", "ayah", "insights"]
    /// "Open in shukr": What's new closes and PrayerTimesView takes the user to `link`.
    static let go = Notification.Name("whatsNewGo")
    /// The pages "Open in shukr" can go to; any other link shows no button.
    static let links: Set<String> = ["salah", "zikr", "settings", "history", "azkar", "map", "names", "ayah", "insights"]

    // MARK: Helpers

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(from s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    /// "today 4:07 AM" · "yesterday 9:12 PM" · "Sep 25, 4:07 AM".
    static func whenLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "today \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday \(time)" }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    static func image(_ name: String) -> UIImage? {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        return Bundle.main.url(forResource: base, withExtension: ext).flatMap { UIImage(contentsOfFile: $0.path) }
    }

    /// The build time in a note's build line ("2.0 (11) · Sep 28 at 4:32 AM · 5b4cdd0").
    static func buildTime(of item: FeedbackItem) -> Date? {
        let parts = item.build.components(separatedBy: " · ")
        guard parts.count >= 2 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d 'at' h:mm a yyyy"
        let year = Calendar.current.component(.year, from: item.created)
        return f.date(from: parts[1].replacingOccurrences(of: "\u{202F}", with: " ") + " \(year)")
    }
}

// MARK: - Carrying v3's state across (once)

/// v3 kept "what's been checked" in several places (a note's Looks good / Still off, chat requests closed or
/// reopened, follow-up notes). The first v4 launch reads them once and records, per ask, what they amount to
/// on its newest change. The old keys are left in place.
///
/// v2 of this (2026-09-29, after the first run on his phone filed asks waiting on him as "with the team"):
/// only EXPLICIT answers count —
/// - Looks good → works; Still off → it's carried on by its follow-up note: once the team built for that
///   note (it's an ask with a change), the follow-up's own ask is the one to check, so this one closes; not
///   built yet → with the team;
/// - a later "works" / Looks good on the same feature, after this change → checked;
/// - a note about something else on the feature no longer counts as an answer (v1's `saw` rule did).
/// Anything else is open: built, and he hasn't said.
@MainActor enum Migration {
    struct Answer: Codable {
        let works: Bool
        let entry: String
        /// "looks good" · "still off" · "followed up" · "checked" (nil in v1's records).
        var how: String? = nil
    }
    // v3 (the third key): only asks whose newest change existed in v3 are carried (Frank / Bradley, 2026-09-29:
    // a fix for a note written on a v4 build was born "checked", because the note isn't a v3 note).
    private static let key = "whatsNew.v4.migrated3"
    private static let doneKey = "whatsNew.v4.migrated3Done"

    static var answers: [String: Answer] = {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Answer].self, from: data)) ?? [:]
    }()

    static func runOnce() {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let d = UserDefaults.standard
        let closed = Set(d.stringArray(forKey: "whatsNew.asked.closed") ?? [])
        let reopened = Set(d.stringArray(forKey: "whatsNew.asked.reopened") ?? [])
        // v3's notes only (a v4 answer names its change and is counted by `status(of:)` itself).
        let items = FeedbackStore.shared.items.filter(\.isV3Note)
        // A phone that never used What's new (a fresh install): everything asked so far is history, not
        // a to-do list — only asks built after this launch come up.
        let fresh = items.isEmpty && closed.isEmpty && reopened.isEmpty && d.object(forKey: "whatsNew.acked") == nil
        let ctx = Context(items: items, v4Notes: Set(FeedbackStore.shared.items.filter { !$0.isV3Note }.map { $0.id.uuidString.lowercased() }),
                          closed: closed, reopened: reopened)
        var out: [String: Answer] = [:]
        var open = 0
        for ask in WhatsNew.asks {
            guard let latest = WhatsNew.entries(ask: ask.id).last else { continue }
            // Only what v3 knew: a change from before v4 carries its converted `commit`; anything newer is v4's
            // to decide (`status(of:)`), never carried.
            guard latest.commit != nil else { open += 1; continue }
            if fresh {
                out[ask.id] = Answer(works: true, entry: latest.id, how: "checked")
            } else if let (works, how) = ctx.earlierAnswer(ask, latest) {
                out[ask.id] = Answer(works: works, entry: latest.id, how: how)
            } else {
                open += 1
            }
        }
        answers = out
        if let data = try? JSONEncoder().encode(out) { d.set(data, forKey: key) }
        d.set(true, forKey: doneKey)
        print("✅ What's new v4: carried \(out.count) answered ask(s) across; \(open) still open")
    }

    private struct Context {
        let items: [FeedbackItem]
        /// Ids of notes written on a v4 build (lowercased).
        let v4Notes: Set<String>
        let closed: Set<String>
        let reopened: Set<String>

        /// (works, how) — nil = still waiting for him.
        func earlierAnswer(_ ask: WhatsNewAsk, _ latest: WhatsNewEntry) -> (Bool, String)? {
            if ask.fromNote {
                // A note written on a v4 build: only his own Works / Not yet on the phone answers it.
                if isV4Note(ask) { return nil }
                guard let note = note(ask) else { return (true, "checked") }      // an old note not on this phone
                if note.closedAt != nil { return (true, "looks good") }
                if note.reopenedAt != nil {
                    return followUp(items.first { $0.followUpOf == note.id }, latest)
                }
                return laterWorks(latest) ? (true, "checked") : nil
            }
            let followUpNote = items.first { $0.followUpOfEntry == latest.id }
            if closed.contains(latest.id) { return (true, "looks good") }
            if reopened.contains(latest.id) || (followUpNote.map { $0.kind != .works } ?? false) {
                return followUp(followUpNote, latest)
            }
            if followUpNote?.kind == .works { return (true, "looks good") }
            // v3 checked a change that also answered a note through that note only (one card, not two).
            if latest.askIDs.contains(where: { WhatsNew.ask($0)?.fromNote == true }) { return (true, "checked") }
            return laterWorks(latest) ? (true, "checked") : nil
        }

        /// Still off: its follow-up note carries it on once the team built for it.
        private func followUp(_ f: FeedbackItem?, _ latest: WhatsNewEntry) -> (Bool, String) {
            if let f, let a = askFor(f), !WhatsNew.entries(ask: a.id).isEmpty { return (true, "followed up") }
            if f == nil && laterWorks(latest) { return (true, "checked") }
            return (false, "still off")
        }

        /// He said the feature is fine after this change: a 👍 on it written on a build that had the change,
        /// Looks good on a note a later change fixed, or Looks good on a later chat request.
        private func laterWorks(_ latest: WhatsNewEntry) -> Bool {
            for i in items where i.topic == latest.topic {
                if i.kind == .works && saw(latest, i) { return true }
                if let c = i.closedAt, c >= latest.when, let a = askFor(i),
                   WhatsNew.entries(ask: a.id).contains(where: { $0.when >= latest.when }) { return true }
            }
            return WhatsNew.entries(topic: latest.topic).contains { closed.contains($0.id) && $0.when >= latest.when }
        }

        private func isV4Note(_ ask: WhatsNewAsk) -> Bool {
            guard let prefix = ask.note?.lowercased() else { return false }
            return v4Notes.contains { $0.hasPrefix(prefix) }
        }
        private func note(_ ask: WhatsNewAsk) -> FeedbackItem? {
            guard let prefix = ask.note?.lowercased() else { return nil }
            return items.first { $0.id.uuidString.lowercased().hasPrefix(prefix) }
        }
        private func askFor(_ item: FeedbackItem) -> WhatsNewAsk? {
            let id = item.id.uuidString.lowercased()
            return WhatsNew.asks.first { $0.fromNote && ($0.note.map { id.hasPrefix($0.lowercased()) } ?? false) }
        }
        /// Was the note written on a build that had this change?
        private func saw(_ entry: WhatsNewEntry, _ item: FeedbackItem) -> Bool {
            let built = WhatsNew.buildTime(of: item) ?? item.created
            return built.addingTimeInterval(60) >= entry.when && item.created >= entry.when
        }
    }

    #if DEBUG
    /// `-whatsNewResetMigration`: run it again (checking the mapping against pulled data).
    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: doneKey)
        UserDefaults.standard.removeObject(forKey: key)
        answers = [:]
    }
    #endif
}

// MARK: - "‹ What's new" after Open in shukr

/// After "Open in shukr" closed the sheet (a pager page, the map): the change to reopen it at.
@MainActor @Observable final class WhatsNewReturn {
    static let shared = WhatsNewReturn()
    /// A change's id.
    var card: String?
}

/// The "‹ What's new" pill after "Open in shukr" left the sheet: tap → What's new again, on the same
/// change; ✕ → gone. On the root page and the map (a full-screen cover hides the root's).
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

// MARK: - Who sees it

/// `available`: What's new itself — DEBUG, or a TestFlight install the owner unlocked (hold the build line
/// 3 s; it stays unlocked through updates). Testers never see it.
/// `beta`: extras testers do get — DEBUG or any TestFlight install (Your reminders' link and Details).
@MainActor final class WhatsNewAccess: ObservableObject {
    static let shared = WhatsNewAccess()
    static let unlockKey = "whatsNew.unlocked"
    #if DEBUG
    @Published private(set) var available = true
    @Published private(set) var beta = true
    #else
    @Published private(set) var available = false
    @Published private(set) var beta = false
    #endif
    /// A TestFlight install that isn't unlocked yet (the build line takes the long press).
    @Published private(set) var canUnlock = false

    private init() {
        #if !DEBUG
        Task { @MainActor in
            if case .verified(let transaction) = try? await AppTransaction.shared, transaction.environment != .production {
                beta = true
                let unlocked = UserDefaults.standard.bool(forKey: Self.unlockKey)
                available = unlocked
                canUnlock = !unlocked
                if unlocked { WhatsNew.writeState() }
            }
        }
        #endif
    }

    func unlock() {
        UserDefaults.standard.set(true, forKey: Self.unlockKey)
        available = true
        canUnlock = false
        WhatsNew.writeState()
    }
}

/// The build line, tappable into What's new where it's allowed; on a locked TestFlight install a 3 s hold
/// unlocks it (for the owner's own phone).
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
        } else if access.canUnlock {
            Text(BuildInfo.line)
                .onLongPressGesture(minimumDuration: 3) {
                    triggerSomeVibration(type: .success)
                    access.unlock()
                }
        } else {
            Text(BuildInfo.line)
        }
    }
}
