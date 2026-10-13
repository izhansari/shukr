//
//  ExploreLean.swift
//  shukr
//
//  Settings → Explore shukr, the lean version (owner, 2026-10-13: "let's just do it … keep your new one as the
//  default"; mockup https://claude.ai/artifact/Bi1NpJaAZ4ekATmw3J2eoc, version 3). Four things on the first screen —
//  the one pick for you and three to try next — then "What you use" folded and "Everything shukr can do": twelve stories,
//  each opening one page. Frank's original page (ExploreShukr.swift) stays one switch away in My Dev Stuff
//  (`ExploreLean.originalKey`), and its cards are the stories for the eight iPhone features.
//
//  The pick (owner: "what's the algorithm?"): every story not fully found is scored —
//  +5 new (shipped in the last 30 days, not opened) · +4 fits your habits (late prayers → widgets; a masjid → your masjid;
//  zikr most days → zikr extras; a watch without the app → the watch) · +3 fits today (Thu / Fri → masjid; evening →
//  zikr extras) · +2 a quick win inside shukr · −3 picked on either of the last two days and not tried. "Not for me"
//  keeps a story out of the pick for 30 days. The pick holds for the day unless it's found or dismissed.
//

import SwiftUI
import SwiftData
import WidgetKit
import WatchConnectivity

// MARK: - The stories

enum ExploreStoryID: String, CaseIterable, Identifiable {
    case widgets, qibla, watch, siri, answer, masjid, map, journey, memories, goals, zikrExtras, learn
    var id: String { rawValue }
}

struct ExploreStory: Identifiable, Hashable {
    static func == (a: ExploreStory, b: ExploreStory) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    let id: ExploreStoryID
    let title: String
    /// What's inside, one line (the Everything list).
    let line: String
    let symbol: String
    /// Its parts and whether each is found (2 of 7 widgets added).
    var parts: [(String, Bool)]
    var isNew = false
    /// The pick's reason, in plain words, when it's the pick.
    var reason = ""
    var score = 0
    var found: Int { parts.filter(\.1).count }
    var total: Int { parts.count }
    var complete: Bool { found == total }
}

enum ExploreLean {
    /// My Dev Stuff: Frank's original page instead (owner: "keep it as something in the dev settings that I can change
    /// back to").
    static let originalKey = "explore.original"
    static func openedKey(_ id: ExploreStoryID) -> String { "explore.opened.\(id.rawValue)" }
    static func dismissedKey(_ id: ExploreStoryID) -> String { "explore.dismissed.\(id.rawValue)" }
    static let pickKey = "explore.pick"            // "yyyy-MM-dd|story"
    static let pickHistoryKey = "explore.pickHistory"   // the last few days' picks, "yyyy-MM-dd|story"

    /// When each story's newest part shipped (New for 30 days, until opened).
    static let shipped: [ExploreStoryID: String] = [.memories: "2026-10-08", .watch: "2026-10-06"]

    static func isNew(_ id: ExploreStoryID, now: Date = Date()) -> Bool {
        guard let day = shipped[id], let date = dayFormatter.date(from: day) else { return false }
        return now.timeIntervalSince(date) < 30 * 86_400 && !UserDefaults.standard.bool(forKey: openedKey(id))
    }
    /// The Settings row's count: new and not opened (owner: a badge only when there's something new).
    static var newCount: Int { ExploreStoryID.allCases.filter { isNew($0) }.count }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
}

// MARK: - What's found, the scores, the pick

@MainActor @Observable final class ExploreLeanModel {
    private(set) var stories: [ExploreStory] = []
    private(set) var pick: ExploreStory?
    private(set) var next: [ExploreStory] = []
    private(set) var using: [ExploreStory] = []
    private(set) var loaded = false
    var foundParts: Int { stories.reduce(0) { $0 + $1.found } }
    var totalParts: Int { stories.reduce(0) { $0 + $1.total } }

    func load(context: ModelContext) async {
        let d = UserDefaults.standard
        let configs: [WidgetInfo] = await withCheckedContinuation { c in
            WidgetCenter.shared.getCurrentConfigurations { c.resume(returning: (try? $0.get()) ?? []) }
        }
        let lockFamilies: Set<WidgetFamily> = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        func home(_ kind: String) -> Bool { configs.contains { $0.kind == kind && !lockFamilies.contains($0.family) } }
        func lock(_ kind: String) -> Bool { configs.contains { $0.kind == kind && lockFamilies.contains($0.family) } }
        var controls = false
        if let added = try? await ControlCenter.shared.currentControls() {
            controls = added.contains { $0.kind.hasPrefix("betternorms.shukr.control") }
        }
        var watchPaired = false, watchInstalled = false
        if WCSession.isSupported() {
            let s = WCSession.default
            watchPaired = s.activationState == .activated && s.isPaired
            watchInstalled = watchPaired && s.isWatchAppInstalled
        }
        await NotificationHealth.shared.refresh()
        let a = NotificationHealth.shared.authorization
        let notifications = a == .authorized || a == .provisional || a == .ephemeral

        // From the store: habits and what's been done.
        let now = Date()
        let twoWeeks = now.addingTimeInterval(-14 * 86_400), month = now.addingTimeInterval(-30 * 86_400)
        let prayers = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted && $0.startTime >= month }))) ?? []
        let lateLately = prayers.filter { $0.startTime >= twoWeeks && ($0.numberScore ?? 100) < 80 }.count
        let atMasjid = prayers.contains { !($0.mosqueName ?? "").isEmpty }
        let jumuah = prayers.contains { $0.name == "Dhuhr" && !($0.mosqueName ?? "").isEmpty
            && Calendar.current.component(.weekday, from: $0.startTime) == 6 }
        let week = now.addingTimeInterval(-7 * 86_400)
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= month }))) ?? []
        let zikrDays = Set(sessions.filter { $0.startTime >= week }.map { Calendar.current.startOfDay(for: $0.startTime) }).count
        let tasbihFatimah = sessions.contains { ($0.mantra?.name ?? $0.title) == PostSalahTasbeeh.mantraName }
        let tasks = ((try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0) > 0
        func opened(_ id: ExploreStoryID) -> Bool { d.bool(forKey: ExploreLean.openedKey(id)) }

        var list: [ExploreStory] = [
            ExploreStory(id: .widgets, title: "Widgets", line: "Home Screen and Lock Screen", symbol: "square.grid.2x2",
                         parts: [("Prayer ring", home(WidgetKinds.prayers)), ("Zikr tasks", home(WidgetKinds.zikr)),
                                 ("Name of the Day", home(WidgetKinds.name)), ("Daily Ayah", home(WidgetKinds.ayah)),
                                 ("Prayer on the Lock Screen", lock(WidgetKinds.prayers)), ("Zikr on the Lock Screen", lock(WidgetKinds.zikr)),
                                 ("Name on the Lock Screen", lock(WidgetKinds.name))]),
            ExploreStory(id: .qibla, title: "Qibla, one tap away", line: "Control Center, the Lock Screen, the Action button",
                         symbol: "location.north.line", parts: [("A shukr control", controls)]),
            ExploreStory(id: .watch, title: "Apple Watch", line: "The app and your watch face", symbol: "applewatch",
                         parts: [("The watch app", watchInstalled)]),
            ExploreStory(id: .siri, title: "Siri and Shortcuts", line: "Mark a prayer with your voice", symbol: "waveform",
                         parts: [("Siri", opened(.siri))]),
            ExploreStory(id: .answer, title: "Answer from a notification", line: "I already prayed · nudge me later",
                         symbol: "bell.badge", parts: [("Notifications on", notifications)]),
            ExploreStory(id: .masjid, title: "Your masjid", line: "Mosques near you, Jumu'ah, a dua on arrival", symbol: "building.columns",
                         parts: [("A masjid starred or prayed at", atMasjid || !MosqueFavorites.all.isEmpty), ("Jumu'ah at a masjid", jumuah),
                                 ("A dua on arrival", d.bool(forKey: MasjidArrival.enabledKey))]),
            ExploreStory(id: .map, title: "The map", line: "Where you prayed, and the qibla", symbol: "map",
                         parts: [("The map", opened(.map))]),
            ExploreStory(id: .journey, title: "How you're doing", line: "Insights and your day's ring", symbol: "chart.pie",
                         parts: [("Insights", opened(.journey))]),
            ExploreStory(id: .memories, title: "Memories", line: "A photo with each prayer", symbol: "photo.stack",
                         parts: [("A prayer photo", !PrayerPhotos.all().isEmpty)]),
            ExploreStory(id: .goals, title: "Daily zikr goals", line: "Tasks with streaks", symbol: "target",
                         parts: [("A daily task", tasks)]),
            ExploreStory(id: .zikrExtras, title: "Zikr extras", line: "Sleep mode and Tasbih Fatimah", symbol: "moon.zzz",
                         parts: [("Sleep mode", d.bool(forKey: SleepMorning.introConfirmedKey)), ("Tasbih Fatimah", tasbihFatimah)]),
            ExploreStory(id: .learn, title: "Learn and reflect", line: "Daily Ayah and the 99 Names", symbol: "book",
                         parts: [("A Daily Ayah revealed", d.object(forKey: "dailyAyah.revealedDay") != nil),
                                 ("A Name learned", !(d.stringArray(forKey: KnownNames.key) ?? []).isEmpty)]),
        ]
        // Only what can apply: the watch only with a watch.
        if !watchPaired { list.removeAll { $0.id == .watch } }

        // The scores.
        let weekday = Calendar.current.component(.weekday, from: now), hour = Calendar.current.component(.hour, from: now)
        let today = ExploreLean.dayFormatter.string(from: now)
        let history = (d.stringArray(forKey: ExploreLean.pickHistoryKey) ?? []).compactMap { entry -> (String, String)? in
            let p = entry.split(separator: "|"); return p.count == 2 ? (String(p[0]), String(p[1])) : nil
        }
        let recent = Set(history.filter { $0.0 != today }.suffix(2).map(\.1))
        for i in list.indices {
            var s = list[i]
            s.isNew = ExploreLean.isNew(s.id, now: now)
            var score = 0, reason = ""
            func add(_ n: Int, _ why: String) { score += n; if reason.isEmpty, !why.isEmpty { reason = why } }
            if s.isNew { add(5, "New in shukr: " + Self.defaultReason(s.id).prefix(1).lowercased() + Self.defaultReason(s.id).dropFirst()) }
            switch s.id {
            case .widgets where lateLately >= 3: add(4, "You often pray near the end of a window. Your Home Screen can show how long is left.")
            case .masjid where atMasjid: add(4, "You pray at a masjid. shukr can count Jumu'ah there and greet you with a dua.")
            case .zikrExtras where zikrDays >= 4: add(4, "You count zikr most days. Sleep mode saves a session when you drift off.")
            case .goals where zikrDays >= 2 && !tasks: add(4, "You count zikr often. A daily goal keeps a streak going.")
            case .watch where !watchInstalled: add(4, "You have an Apple Watch. Mark prayers and count zikr from your wrist.")
            default: break
            }
            if s.id == .masjid, weekday == 5 || weekday == 6 { add(3, "It's almost Jumu'ah. At your masjid it counts as Jumu'ah, full marks.") }
            if s.id == .zikrExtras, hour >= 19 { add(3, "An evening zikr can end on its own when you fall asleep.") }
            if [.masjid, .map, .journey, .memories, .learn, .goals].contains(s.id) { add(2, "") }
            if recent.contains(s.id.rawValue) { score -= 3 }
            s.score = score
            s.reason = reason.isEmpty ? Self.defaultReason(s.id) : reason
            list[i] = s
        }
        stories = list

        // The pick: today's, if it's still to try; else the best that isn't dismissed.
        let dismissedRecently: (ExploreStoryID) -> Bool = { id in
            let t = d.double(forKey: ExploreLean.dismissedKey(id)); return t > 0 && now.timeIntervalSince1970 - t < 30 * 86_400
        }
        let order = Dictionary(uniqueKeysWithValues: list.enumerated().map { ($1.id, $0) })
        let candidates = list.filter { !$0.complete && !dismissedRecently($0.id) }
            .sorted { a, b in a.score != b.score ? a.score > b.score : (order[a.id] ?? 0) < (order[b.id] ?? 0) }
        var chosen: ExploreStory?
        if let saved = d.string(forKey: ExploreLean.pickKey), saved.hasPrefix(today + "|"),
           let id = ExploreStoryID(rawValue: String(saved.dropFirst(today.count + 1))) {
            chosen = candidates.first { $0.id == id }
        }
        if chosen == nil, let best = candidates.first {
            chosen = best
            d.set("\(today)|\(best.id.rawValue)", forKey: ExploreLean.pickKey)
            d.set(Array((history.map { "\($0.0)|\($0.1)" } + ["\(today)|\(best.id.rawValue)"]).suffix(7)), forKey: ExploreLean.pickHistoryKey)
        }
        pick = chosen
        next = Array(candidates.filter { $0.id != chosen?.id }.prefix(3))
        using = list.filter(\.complete)
        loaded = true
    }

    /// "Not for me": out of the pick for 30 days (still in Everything).
    func dismissPick(context: ModelContext) async {
        guard let pick else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ExploreLean.dismissedKey(pick.id))
        UserDefaults.standard.removeObject(forKey: ExploreLean.pickKey)
        await load(context: context)
    }

    static func defaultReason(_ id: ExploreStoryID) -> String {
        switch id {
        case .widgets: "Your prayer and how long is left, without opening shukr."
        case .qibla: "The qibla from anywhere, even inside another app."
        case .watch: "Your prayers and your zikr on your wrist."
        case .siri: "Mark a prayer or ask the time left, without picking up your phone."
        case .answer: "Mark a prayer right from its notification."
        case .masjid: "Mosques near you, and Jumu'ah counted when you're there."
        case .map: "Every prayer you've marked, where you prayed it."
        case .journey: "See which prayer needs you most."
        case .memories: "A photo after you pray, kept day by day."
        case .goals: "A daily goal for a zikr, with a streak."
        case .zikrExtras: "Sleep mode and Tasbih Fatimah after every prayer."
        case .learn: "A verse a day, and the 99 Names one by one."
        }
    }
}

// MARK: - The first screen

struct ExploreLeanPage: View {
    @State private var model = ExploreLeanModel()
    @Environment(\.modelContext) private var context
    /// DEBUG `-demoExploreStory widgets`: that story, pushed once the page has loaded (screenshots).
    @State private var demoStory: ExploreStory?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let pick = model.pick { PickedCard(story: pick) { Task { await model.dismissPick(context: context) } } }
                if !model.next.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Next to try").font(.system(.headline, design: .rounded)).padding(.horizontal, 4)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(model.next) { story in
                                    NavigationLink { ExploreStoryPage(story: story) } label: { NextCard(story: story) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, -16)
                    }
                }
                VStack(spacing: 10) {
                    if !model.using.isEmpty {
                        NavigationLink { ExploreEverythingPage(model: model, onlyUsing: true) } label: {
                            FoldRow(title: "What you use",
                                    line: model.using.prefix(3).map(\.title).joined(separator: ", ")
                                        + (model.using.count > 3 ? " and \(model.using.count - 3) more" : ""),
                                    filled: false)
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink { ExploreEverythingPage(model: model) } label: {
                        FoldRow(title: "Everything shukr can do", line: "\(model.stories.count) stories", filled: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .opacity(model.loaded ? 1 : 0)
            .animation(.easeOut(duration: 0.25), value: model.loaded)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Explore shukr")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task {
            await model.load(context: context)
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "demoExploreStory"), let id = ExploreStoryID(rawValue: raw) {
                demoStory = model.stories.first { $0.id == id }
            }
            #endif
        }
        .navigationDestination(item: $demoStory) { ExploreStoryPage(story: $0) }
        // Back from the Home Screen or Control Center: what was just added counts.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load(context: context) }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Get more from shukr").font(.system(.title2, design: .rounded, weight: .bold))
                Text("Picked for how you use it.").font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                Circle().trim(from: 0, to: model.totalParts > 0 ? CGFloat(model.foundParts) / CGFloat(model.totalParts) : 0)
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(model.foundParts)").font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                    Text("of \(model.totalParts)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 58, height: 58)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.foundParts) of \(model.totalParts) found")
        }
        .padding(.horizontal, 4)
    }
}

/// The one pick: its picture, the reason in plain words, Show me / Not for me.
private struct PickedCard: View {
    let story: ExploreStory
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExploreStoryPicture(id: story.id).frame(height: 170).frame(maxWidth: .infinity).clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text("PICKED FOR YOU").font(.system(.caption2, design: .rounded, weight: .heavy)).tracking(0.8).opacity(0.8)
                Text(story.title).font(.system(.title3, design: .rounded, weight: .bold))
                Text(story.reason).font(.system(.subheadline, design: .rounded)).opacity(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    NavigationLink { ExploreStoryPage(story: story) } label: {
                        Text("Show me").font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.sage)
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    Button("Not for me", action: dismiss)
                        .font(.system(.footnote, design: .rounded)).opacity(0.75).buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .background(LinearGradient(colors: [Color.sage, Color.sage.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct NextCard: View {
    let story: ExploreStory
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExploreStoryPicture(id: story.id).frame(width: 156, height: 96).clipped()
            VStack(alignment: .leading, spacing: 5) {
                Text(story.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                ExploreTag(story: story)
            }
            .padding(10)
            .frame(width: 156, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FoldRow: View {
    let title: String, line: String, filled: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .rounded, weight: filled ? .semibold : .regular))
                Text(line).font(.system(.footnote, design: .rounded)).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).opacity(0.6)
        }
        .foregroundStyle(filled ? Color.white : Color.primary)
        .padding(.horizontal, 16).frame(minHeight: 58)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(filled ? AnyShapeStyle(Color.sage) : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
        .contentShape(Rectangle())
    }
}

/// New · 2 of 7 · Try it · ✓ Using.
private struct ExploreTag: View {
    let story: ExploreStory
    var body: some View {
        let (text, strong): (String, Bool) =
            story.isNew ? ("New", true)
            : story.complete ? ("✓ Using", false)
            : story.total > 1 && story.found > 0 ? ("\(story.found) of \(story.total)", false)
            : ("Try it", false)
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(strong ? Color.white : Color.sage)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(strong ? Color.sage : Color.sage.opacity(story.complete ? 0 : 0.14)))
    }
}

// MARK: - Everything

struct ExploreEverythingPage: View {
    let model: ExploreLeanModel
    var onlyUsing = false
    var body: some View {
        List {
            ForEach(onlyUsing ? model.using : model.stories) { story in
                NavigationLink { ExploreStoryPage(story: story) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: story.symbol)
                            .font(.system(size: 17, weight: .medium)).foregroundStyle(Color.sage)
                            .frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.sage.opacity(0.14)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(story.title)
                            Text(story.line).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        ExploreTag(story: story)
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .navigationTitle(onlyUsing ? "What you use" : "Everything")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - A story

struct ExploreStoryPage: View {
    let story: ExploreStory
    @State private var lockSide = false
    @AppStorage(MasjidArrival.enabledKey) private var arrivalDuas = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .onAppear { UserDefaults.standard.set(true, forKey: ExploreLean.openedKey(story.id)) }
    }

    @ViewBuilder private var content: some View {
        switch story.id {
        case .widgets:
            // The variations live inside the story (mockup v3): Home Screen ⇄ Lock Screen.
            Picker("Where", selection: $lockSide) {
                Text("Home Screen").tag(false)
                Text("Lock Screen").tag(true)
            }
            .pickerStyle(.segmented)
            if lockSide { ExploreFeatureCard(feature: .lock) }
            else {
                ExploreFeatureCard(feature: .home)
                ExploreFeatureCard(feature: .moreWidgets)
            }
        case .qibla: ExploreFeatureCard(feature: .controls)
        case .watch: ExploreFeatureCard(feature: .watch)
        case .siri: ExploreFeatureCard(feature: .siri)
        case .answer: ExploreFeatureCard(feature: .notifications)
        case .memories: ExploreFeatureCard(feature: .memories)
        case .masjid:
            ExploreCard(title: "Your masjid", why: "Find mosques near you, and let shukr notice when you pray at one.",
                        features: [("building.columns", "Mosques near you", "The nearest first, with drive and walk times, Look Around and directions."),
                                   ("star", "Star yours", "Your masjid gets its own pin."),
                                   ("checkmark.seal", "Jumu'ah counted", "Friday's Dhuhr at a masjid counts as Jumu'ah, full marks."),
                                   ("hands.sparkles", "A dua when you arrive", "Switch it on below; shukr greets you at your masjid's door.")],
                        action: ("Find mosques near me", { go("map") })) { ExploreStoryPicture(id: .masjid) }
            // The switch is only in the setup otherwise: here it just does it (it asks for "Always" location).
            Toggle(isOn: Binding(get: { arrivalDuas }, set: { MasjidArrival.shared.setEnabled($0); arrivalDuas = $0 })) {
                Label("A dua when you arrive", systemImage: "hands.sparkles")
            }
            .tint(Color.sage)
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        case .map:
            ExploreCard(title: "The map", why: "Every prayer you've marked, where you prayed it, and the qibla from where you stand.",
                        features: [("mappin.and.ellipse", "Your prayers", "Coloured by how you did; filter by prayer and dates."),
                                   ("location.north.line", "Qibla up", "The map turns so the qibla points up your screen.")],
                        action: ("Open the map", { go("map") })) { ExploreStoryPicture(id: .map) }
        case .journey:
            ExploreCard(title: "How you're doing", why: "Which prayer needs you most, how you're scoring, and how consistent you are.",
                        features: [("chart.line.uptrend.xyaxis", "Getting better?", "Each prayer ranked by its recent score, with an 8-week trend."),
                                   ("circle.circle", "Your day in one ring", "After your last prayer, each prayer's fifth in its colour.")],
                        action: ("Open Insights", { go("insights") })) { ExploreStoryPicture(id: .journey) }
        case .goals:
            ExploreCard(title: "Daily zikr goals", why: "Pick a zikr and a daily goal; shukr keeps your streak.",
                        features: [("target", "A count or minutes", "33 a day, or 5 minutes, your choice."),
                                   ("flame", "Streaks", "Every day you meet it, the streak grows."),
                                   ("bell", "A reminder", "At a time or around a prayer, if you'd like.")],
                        action: ("Go to Zikr", { go("zikr") })) { ExploreStoryPicture(id: .goals) }
        case .zikrExtras:
            ExploreCard(title: "Zikr extras", why: "Small things that make counting easier.",
                        features: [("moon.zzz", "Sleep mode", "Counting in bed? The session saves itself when you fall asleep. Turn it on from a session's pause screen."),
                                   ("33.circle", "Tasbih Fatimah", "33 · 33 · 34 after every prayer, offered when you mark one."),
                                   ("waveform", "Your own voice memo", "Record how a zikr is said, on its card in Azkar.")],
                        action: ("Open Azkar", { go("azkar") })) { ExploreStoryPicture(id: .zikrExtras) }
        case .learn:
            ExploreCard(title: "Learn and reflect", why: "A little every day.",
                        features: [("book", "Daily Ayah", "A verse a day, revealed by you, with a card to share."),
                                   ("sparkles", "The 99 Names", "Each with its meaning, and flashcards to learn them.")],
                        action: ("Open today's verse", { go("ayah") })) { ExploreStoryPicture(id: .learn) }
        }
    }

    /// Off to that part of shukr (What's new's "Open in shukr" route: covers close first).
    private func go(_ link: String) {
        NotificationCenter.default.post(name: WhatsNew.go, object: link)
    }
}

// MARK: - The pictures (the sage panel, like the original's)

struct ExploreStoryPicture: View {
    let id: ExploreStoryID
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.sage.opacity(0.55), Color.sage.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
            picture
        }
    }

    @ViewBuilder private var picture: some View {
        switch id {
        case .widgets: HomeScreenPicture()
        case .qibla: ControlCenterPicture()
        case .watch: WatchPicture()
        case .siri: SiriPicture()
        case .answer: NotificationsPicture()
        case .memories: MemoriesPicture()
        case .masjid:
            VStack(alignment: .leading, spacing: 4) {
                Text(ExplorePreset.masjid).font(.system(.subheadline, design: .rounded, weight: .semibold))
                Label("Jumu'ah counts here", systemImage: "checkmark.seal.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(Color.sage)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        case .map:
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    Circle().fill(i == 2 ? Color.yellow : Color.green).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: [-50, -10, 30, 60, -30][i], y: [-20, 15, -30, 20, 35][i])
                }
                Image(systemName: "location.north.line.fill").font(.title2).foregroundStyle(Color.sage)
            }
        case .journey:
            HStack(spacing: 8) {
                MiniRing(progress: 0.86, width: 6).frame(width: 40, height: 40)
                MiniRing(progress: 0.64, width: 6).frame(width: 40, height: 40)
                MiniRing(progress: 0.92, width: 6).frame(width: 40, height: 40)
            }
        case .goals:
            HStack(spacing: 10) {
                MiniRing(progress: 1, width: 6).frame(width: 46, height: 46)
                MiniRing(progress: 0.6, width: 6).frame(width: 46, height: 46)
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(Color.sage)
            }
        case .zikrExtras:
            HStack(spacing: 14) {
                Image(systemName: "moon.fill").font(.system(size: 34)).foregroundStyle(.white.opacity(0.9))
                Text("33 · 33 · 34").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(.white)
            }
        case .learn:
            VStack(spacing: 2) {
                Text("ٱلرَّحِيمُ").font(.system(size: 30))
                Text("The Most Merciful").font(.system(.caption, design: .rounded))
            }
            .foregroundStyle(.white)
        }
    }
}
