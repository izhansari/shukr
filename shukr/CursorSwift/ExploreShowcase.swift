//
//  ExploreShowcase.swift
//  shukr
//
//  Settings → Explore shukr, the showcase (owner, 2026-10-13: "make the other version you had before this … your pics
//  looked better in the artifact"; mockup version 2, https://claude.ai/artifact/Bi1NpJaAZ4ekATmw3J2eoc). Grouped by
//  moments — Home Screen, Lock Screen, wrist and nightstand, hands-free, around you, your journey, your zikr — every widget
//  its own card, each card a live picture with today's own prayer, a headline that says what you get, and a tag
//  (New · Try it · ✓ Using). A tap opens its story: a big picture, one sentence, three good things, one button.
//  The default; My Dev Stuff → Explore page picks Lean (ExploreLean.swift) or Frank's original (ExploreShukr.swift).
//

import SwiftUI
import SwiftData
import AppIntents
import WidgetKit
import WatchConnectivity

// MARK: - Which page

enum ExplorePageVariant: String, CaseIterable, Identifiable {
    case simple, grouped, showcase, lean, original
    var id: String { rawValue }
    /// A new key with the simple page (owner 2026-10-13): a phone that had picked another one in My Dev Stuff starts on it.
    static let key = "explore.variant2"
    var label: String {
        switch self {
        case .simple: "Simple"
        case .grouped: "Grouped"
        case .showcase: "Showcase"
        case .lean: "Lean"
        case .original: "Original"
        }
    }
}

// MARK: - The cards

enum ShowcaseCardID: String, CaseIterable, Identifiable {
    case homePrayers, homeZikr, homeName, homeAyah
    case lockTime, lockCountdown, lockName, lockControls
    case watchApp, watchFace, standby
    case siri, answer, controlCenter, actionButton
    case prayersMap, jumuah, mosques
    case memories, insights
    case sleep, tasbihFatimah, goals
    // The grouped page's members (ExploreGrouped.swift): each Siri phrase, each control.
    case siriTimeLeft, siriPrayerTime, siriTodaysTimes, siriIPrayed, siriFajrAlarm, siriOpenPage, siriTasbihFatimah,
         siriZikrTasks, siriMosques, siriPrayedHere
    case ccPrayer, ccPrayed, ccFajrAlarm, ccQibla, ccZikr
    var id: String { rawValue }
    var isSiri: Bool { rawValue.hasPrefix("siri") }
    var isControl: Bool { rawValue.hasPrefix("cc") }
}

struct ShowcaseSection: Identifiable {
    let id: String
    let title: String
    let note: String
    /// Every card at once, two by two (the widget sections), or a row you swipe.
    let grid: Bool
    var cards: [ShowcaseCard]
}

struct ShowcaseCard: Identifiable, Hashable {
    static func == (a: ShowcaseCard, b: ShowcaseCard) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    let id: ShowcaseCardID
    let headline: String
    var using = false
    var isNew = false
}

enum ExploreShowcase {
    static func openedKey(_ id: ShowcaseCardID) -> String { "explore.showcase.opened.\(id.rawValue)" }
    /// When each card's feature shipped: New for 30 days, until opened.
    static let shipped: [ShowcaseCardID: String] = [.memories: "2026-10-08", .lockTime: "2026-09-29"]
    static func isNew(_ id: ShowcaseCardID, now: Date = Date()) -> Bool {
        guard let day = shipped[id], let date = ExploreLean.dayFormatter.date(from: day) else { return false }
        return now.timeIntervalSince(date) < 30 * 86_400 && !UserDefaults.standard.bool(forKey: openedKey(id))
    }
    static var newCount: Int { ShowcaseCardID.allCases.filter { isNew($0) }.count }

    /// An iPhone with an Action button (15 Pro and later, every 16 and later).
    static var hasActionButton: Bool {
        var machine = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        if machine.isEmpty {
            var info = utsname(); uname(&info)
            machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        }
        guard machine.hasPrefix("iPhone"), let comma = machine.firstIndex(of: ","),
              let major = Int(machine.dropFirst(6).prefix(upTo: comma)) else { return false }
        let minor = Int(machine[machine.index(after: comma)...]) ?? 0
        return major >= 17 || (major == 16 && minor <= 2)
    }
}

@MainActor @Observable final class ShowcaseModel {
    private(set) var sections: [ShowcaseSection] = []
    private(set) var loaded = false
    var found: Int { sections.flatMap(\.cards).filter(\.using).count }
    /// The grouped page's extra members (each Siri phrase, each control), not shown on this page.
    private(set) var extras: [ShowcaseCard] = []
    /// Every card that applies, by id (the grouped page reads its members from here).
    var byID: [ShowcaseCardID: ShowcaseCard] { Dictionary((sections.flatMap(\.cards) + extras).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    var total: Int { sections.flatMap(\.cards).count }

    /// When it last looked (`refreshIfStale`).
    private var loadedAt = Date.distantPast

    /// Back in the app: looked again only if it's been a while — pulling Control Center or Notification Center down on the
    /// page made the app active again and re-ran every check, re-rendering the whole page (perf-recheck, 2026-10-14).
    func refreshIfStale(context: ModelContext) async {
        guard Date().timeIntervalSince(loadedAt) > 30 else { return }
        await load(context: context)
    }

    func load(context: ModelContext) async {
        loadedAt = Date()
        let d = UserDefaults.standard
        let configs: [WidgetInfo] = await withCheckedContinuation { c in
            WidgetCenter.shared.getCurrentConfigurations { c.resume(returning: (try? $0.get()) ?? []) }
        }
        func on(_ kind: String, _ families: Set<WidgetFamily>) -> Bool { configs.contains { $0.kind == kind && families.contains($0.family) } }
        let homeFamilies: Set<WidgetFamily> = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        var controls = false
        var controlKinds = Set<String>()
        if let added = try? await ControlCenter.shared.currentControls() {
            controlKinds = Set(added.map(\.kind))
            controls = added.contains { $0.kind.hasPrefix("betternorms.shukr.control") }
        }
        var watchPaired = false, watchInstalled = false
        if WCSession.isSupported() {
            let s = WCSession.default
            watchPaired = s.activationState == .activated && s.isPaired
            watchInstalled = watchPaired && s.isWatchAppInstalled
        }
        #if DEBUG
        // `-demoExploreWatch YES`: the watch items without a paired watch (the simulator has none).
        if UserDefaults.standard.bool(forKey: "demoExploreWatch") { watchPaired = true }
        #endif
        await NotificationHealth.shared.refresh()
        let a = NotificationHealth.shared.authorization
        let month = Date().addingTimeInterval(-30 * 86_400)
        let prayers = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted && $0.startTime >= month }))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= month }))) ?? []
        func opened(_ id: ShowcaseCardID) -> Bool { d.bool(forKey: ExploreShowcase.openedKey(id)) }
        func card(_ id: ShowcaseCardID, _ headline: String, _ using: Bool) -> ShowcaseCard {
            ShowcaseCard(id: id, headline: headline, using: using, isNew: ExploreShowcase.isNew(id))
        }

        var list: [ShowcaseSection] = [
            ShowcaseSection(id: "home", title: "On your Home Screen", note: "4 widgets", grid: true, cards: [
                card(.homePrayers, "Your prayer ring, marked with a tap", on(WidgetKinds.prayers, homeFamilies)),
                card(.homeZikr, "Today's zikr tasks at a glance", on(WidgetKinds.zikr, homeFamilies)),
                card(.homeName, "One of the 99 Names each day", on(WidgetKinds.name, homeFamilies)),
                card(.homeAyah, "Today's verse, once you reveal it", on(WidgetKinds.ayah, homeFamilies)),
            ]),
            ShowcaseSection(id: "lock", title: "On your Lock Screen", note: "no unlocking", grid: true, cards: [
                card(.lockTime, "Time left in the last hour", on(WidgetKinds.prayers, [.accessoryCircular])),
                card(.lockCountdown, "A countdown and what's next", on(WidgetKinds.prayers, [.accessoryRectangular])),
                card(.lockName, "The Name of the Day above the time", on(WidgetKinds.name, [.accessoryInline, .accessoryRectangular])),
                card(.lockControls, "Qibla and tasbeeh on the Lock Screen", controls),
            ]),
            ShowcaseSection(id: "wrist", title: "Wrist and nightstand", note: "", grid: false, cards: [
                card(.watchApp, "Mark prayers from your wrist", watchInstalled),
                card(.watchFace, "The ring on your watch face", opened(.watchFace)),
                card(.standby, "Your ring on the nightstand", opened(.standby)),
            ]),
            ShowcaseSection(id: "hands", title: "Hands-free", note: "a tap or a word", grid: false, cards: [
                card(.siri, "Ask Siri to mark a prayer", opened(.siri)),
                card(.answer, "Answer right from the notification", a == .authorized || a == .provisional || a == .ephemeral),
                card(.controlCenter, "Qibla in Control Center", controls),
                card(.actionButton, "Qibla on your Action button", opened(.actionButton)),
            ]),
            ShowcaseSection(id: "around", title: "Around you", note: "", grid: false, cards: [
                card(.prayersMap, "Every prayer, where you prayed it", opened(.prayersMap)),
                card(.jumuah, "Jumu'ah counted at the masjid", prayers.contains { $0.name == "Dhuhr" && !($0.mosqueName ?? "").isEmpty
                    && Calendar.current.component(.weekday, from: $0.startTime) == 6 }),
                card(.mosques, "Mosques near you", !MosqueFavorites.all.isEmpty || opened(.mosques)),
            ]),
            ShowcaseSection(id: "journey", title: "Your journey", note: "", grid: false, cards: [
                card(.memories, "A photo with each prayer", !PrayerPhotos.all().isEmpty),
                card(.insights, "See which prayer needs you most", opened(.insights)),
            ]),
            ShowcaseSection(id: "zikr", title: "For your zikr", note: "", grid: false, cards: [
                card(.sleep, "Count until you fall asleep", d.bool(forKey: SleepMorning.introConfirmedKey)),
                card(.tasbihFatimah, "Tasbih Fatimah after every prayer",
                     sessions.contains { ($0.mantra?.name ?? $0.title) == PostSalahTasbeeh.mantraName }),
                card(.goals, "A daily task with a streak", ((try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0) > 0),
            ]),
        ]
        // Only what can apply: watch cards with a watch, the Action button on phones that have one.
        for i in list.indices {
            list[i].cards.removeAll { ($0.id == .watchApp || $0.id == .watchFace) && !watchPaired }
            list[i].cards.removeAll { $0.id == .actionButton && !ExploreShowcase.hasActionButton }
            // The rows you swipe: New first, then to try, then what you use. The widget grids keep their places.
            if !list[i].grid {
                list[i].cards.sort { rank($0) < rank($1) }
            }
        }
        sections = list.filter { !$0.cards.isEmpty }
        // Each Siri phrase counts once its story has been opened (iOS doesn't say which phrases ran); each control once
        // it's placed (Control Center, a Lock Screen button or the Action button — iOS tells us which).
        let siri: [ShowcaseCardID] = [.siriTimeLeft, .siriPrayerTime, .siriTodaysTimes, .siriIPrayed, .siriFajrAlarm, .siriOpenPage,
                                      .siriTasbihFatimah, .siriZikrTasks, .siriMosques, .siriPrayedHere]
        let controlKind: [ShowcaseCardID: String] = [.ccPrayer: "prayer", .ccPrayed: "prayed", .ccFajrAlarm: "fajrAlarm",
                                                    .ccQibla: "qibla", .ccZikr: "tasbeeh"]
        extras = siri.map { card($0, ShowcaseStory.of($0).title, opened($0)) }
            + [.ccPrayer, .ccPrayed, .ccFajrAlarm, .ccQibla, .ccZikr].map { id in
                card(id, ShowcaseStory.of(id).title, controlKinds.contains("betternorms.shukr.control." + (controlKind[id] ?? "")))
            }
        loaded = true
    }

    private func rank(_ c: ShowcaseCard) -> Int { c.isNew ? 0 : c.using ? 2 : 1 }
}

// MARK: - The page

struct ExploreShowcasePage: View {
    @State private var model = ShowcaseModel()
    @Environment(\.modelContext) private var context
    /// DEBUG `-demoExploreCard lockTime`: that story, pushed once the page has loaded (screenshots).
    @State private var demoCard: ShowcaseCard?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.title).font(.system(.title3, design: .rounded, weight: .bold))
                            Spacer()
                            if !section.note.isEmpty {
                                Text(section.note).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        if section.grid {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                                ForEach(section.cards) { link($0, width: nil) }
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(section.cards) { link($0, width: 200) }
                                }
                                .padding(.horizontal, 16)
                            }
                            .padding(.horizontal, -16)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
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
            if let raw = UserDefaults.standard.string(forKey: "demoExploreCard"), let id = ShowcaseCardID(rawValue: raw) {
                demoCard = model.sections.flatMap(\.cards).first { $0.id == id }
            }
            #endif
        }
        .navigationDestination(item: $demoCard) { ShowcaseStoryPage(card: $0) }
        // Back from the Home Screen or Control Center: what was just added counts.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshIfStale(context: context) }
        }
    }

    private func link(_ card: ShowcaseCard, width: CGFloat?) -> some View {
        NavigationLink { ShowcaseStoryPage(card: card) } label: { ShowcaseCardView(card: card, width: width) }
            .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Get more from shukr").font(.system(.title2, design: .rounded, weight: .heavy))
                Text("Things shukr can do that most people miss.").font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 6)
                Circle().trim(from: 0, to: model.total > 0 ? CGFloat(model.found) / CGFloat(model.total) : 0)
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(model.found)").font(.system(.headline, design: .rounded, weight: .heavy)).monospacedDigit()
                    Text("of \(model.total)").font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.found) of \(model.total) found")
        }
        .padding(.horizontal, 4)
    }
}

/// A card: its picture, its headline, its tag.
private struct ShowcaseCardView: View {
    let card: ShowcaseCard
    let width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShowcasePicture(id: card.id, compact: width == nil)
                .frame(height: width == nil ? 108 : 124)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(card.headline)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                tag
            }
            .padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 12)
        }
        .frame(width: width)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private var tag: some View {
        let (text, strong, quiet): (String, Bool, Bool) =
            card.isNew ? ("New", true, false) : card.using ? ("✓ Using", false, true) : ("Try it", false, false)
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(strong ? Color.white : quiet ? Color.secondary : Color.sage)
            .padding(.horizontal, quiet ? 0 : 8).padding(.vertical, 3)
            .background(Capsule().fill(strong ? Color.sage : quiet ? Color.clear : Color.sage.opacity(0.14)))
    }
}

// MARK: - A story

struct ShowcaseStoryPage: View {
    let card: ShowcaseCard
    /// The pager marks a page opened when it's the one shown (its neighbours are built early).
    var marksOpened = true
    /// The page's side margin.
    var sideInset: CGFloat = 16
    /// In the pager: just the words and buttons, no picture, no scroll view of its own (owner: only the picture pages).
    var embedded = false
    @AppStorage(MasjidArrival.enabledKey) private var arrivalDuas = false

    var body: some View {
        if embedded {
            details
        } else {
            ScrollView { details }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .fontDesign(.rounded)
                .onAppear { if marksOpened { UserDefaults.standard.set(true, forKey: ExploreShowcase.openedKey(card.id)) } }
        }
    }

    /// The page: its picture (not when embedded — the pager pages the pictures itself), then the words and buttons.
    private var details: some View {
        let s = ShowcaseStory.of(card.id)
        return VStack(alignment: .leading, spacing: 16) {
                if !embedded {
                    ShowcasePicture(id: card.id, big: true)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    // Its name small, then what's good about it as the headline (owner: get across what's cool about it).
                    if let hook = s.hook {
                        ExploreEyebrow(text: s.title)
                        Text(hook).font(.system(.title2, design: .rounded, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(s.title).font(.system(.title2, design: .rounded, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(s.lead).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // What it does: its own symbol and name per point (decision explore-detail-layout A).
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(s.points.enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: point.symbol)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.sage)
                                .frame(width: 28, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(point.name).font(.system(.subheadline, design: .rounded, weight: .semibold))
                                Text(point.line).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                // Parked with the duas (`MasjidArrival.parked`): it asked for "Always" and then did nothing.
                if !MasjidArrival.parked, card.id == .mosques || card.id == .jumuah {
                    // The arrival dua's switch was only in the setup: here it just does it (asks for "Always").
                    Toggle(isOn: Binding(get: { arrivalDuas }, set: { MasjidArrival.shared.setEnabled($0); arrivalDuas = $0 })) {
                        Label("A dua when you arrive", systemImage: "hands.sparkles")
                    }
                    .tint(Color.sage)
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                }
                // How to add / run / use it, right on the page: the steps are short (no "Show me how").
                if let how = s.how, !s.steps.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(how).font(.system(.footnote, design: .rounded, weight: .semibold))
                            .textCase(.uppercase).foregroundStyle(.secondary)
                        ForEach(Array(s.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Color.sage)
                                    .frame(width: 20, height: 20).background(Circle().fill(Color.sage.opacity(0.15)))
                                Text(step).font(.system(.subheadline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                // One button, only when it does something. (Shortcuts' own link only opens shukr's whole page there — iOS
                // can't open one tile's — so it sits on the Shortcuts section's page, not each tile's.)
                if let action = s.action, !s.shortcuts {
                    Button {
                        triggerSomeVibration(type: .light)
                        if let link = s.link { NotificationCenter.default.post(name: WhatsNew.go, object: link) }
                        else if s.memories { MemoriesPresenter.shared.open = true }
                    } label: {
                        Text(action)
                            .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Capsule().fill(Color.sage))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, embedded ? 0 : 16).padding(.horizontal, sideInset)
    }
}

/// Each card's story: its name, a headline saying what's good about it, what it is in plain words, the points the words
/// don't already make, and its button (a link into shukr, Memories, or steps).
/// An item's page (decision explore-detail-layout A, owner: "pretty easily manageable and it applies to all of our different
/// pages"): one sentence, what it does as 2–4 points each with its own symbol and name (as many as it really has), how to
/// add / run / use it shown right on the page, and a button only when it does something.
struct ShowcaseStory {
    struct Point { let symbol: String; let name: String; let line: String }
    /// Its name, small above the headline (what you'd search for).
    let title: String
    /// What's good about it, as the headline (owner: "really want to … get the point across of what is cool about each one").
    var hook: String? = nil
    /// What it is and what it does for you, in plain words.
    let lead: String
    let points: [Point]
    var how: String? = nil
    var steps: [String] = []
    /// The one button, when it does something: a `WhatsNew.go` link, Memories, or shukr's tiles in Shortcuts.
    var action: String? = nil
    var link: String? = nil
    var memories = false
    var shortcuts = false

    private static func p(_ symbol: String, _ name: String, _ line: String) -> Point { Point(symbol: symbol, name: name, line: line) }
    static let homeSteps = ["Touch and hold an empty spot on your Home Screen", "Tap Edit, then Add Widget", "Search shukr and pick it"]
    static let lockSteps = ["Touch and hold your Lock Screen, then tap Customize", "Tap under the clock", "Find shukr and tap it"]
    private static func control(_ name: String, _ hook: String, _ lead: String, _ points: [Point]) -> ShowcaseStory {
        ShowcaseStory(title: name, hook: hook, lead: lead, points: points, how: "How to add it",
                      steps: ["Swipe down from the top-right corner, tap +, then Add a Control", "Search shukr and tap \(name)",
                              "Or on a Lock Screen button or the Action button"])
    }
    /// A Shortcuts tile (owner: Shortcuts and their cards first; Siri one point).
    private static func tile(_ name: String, _ hook: String, _ lead: String, _ points: [Point], siri: String) -> ShowcaseStory {
        ShowcaseStory(title: name, hook: hook, lead: lead, points: points + [p("waveform", "Or ask Siri", siri)], how: "How to run it",
                      steps: ["Open Shortcuts and tap shukr", "Tap \(name)", "Or set it on the Action button: Settings → Action Button"],
                      action: "", shortcuts: true)
    }

    static func of(_ id: ShowcaseCardID) -> ShowcaseStory {
        switch id {
        // Home Screen
        // The one to have (owner: "it's basically a mini version of the app and salah page on your home screen with
        // everything you need"): its picture is the one you can play with.
        case .homePrayers: ShowcaseStory(title: "Prayers widget", hook: "The Salah page, on your Home Screen",
            lead: "Everything the Salah page gives you, without opening shukr: the prayer that's on and how long you have, today's times one tap away, and a ✓ to mark it prayed. Try it above — it works like the real one.",
            points: [p("circle.dashed", "The ring you know", "Green while you're early, then yellow, then red"),
                     p("checkmark.circle", "Mark it right there", "Marked and scored; it moves on to the next prayer"),
                     p("list.bullet", "All five, one tap", "The arrow shows today's times"),
                     p("square.grid.2x2", "Corners you choose", "Qibla, Zikr, Daily Ayah or the 99 Names")],
            how: "How to add it", steps: homeSteps)
        case .homeZikr: ShowcaseStory(title: "Zikr tasks", hook: "Today's zikr, waiting where you'll see it",
            lead: "Your zikr tasks for today and how far along each one is. Tap one and shukr opens straight into counting it.",
            points: [p("circle.dotted.circle", "One ring for the day", "All your tasks at a glance"),
                     p("checkmark.circle", "What's left", "Finished tasks are ticked off")],
            how: "How to add it", steps: homeSteps)
        case .homeName: ShowcaseStory(title: "Name of the Day", hook: "Learn one of Allah's 99 Names each day",
            lead: "A new Name every day, in Arabic with its meaning, on a dark card that suits any Home Screen.",
            points: [p("calendar", "A new one each day", "The same Name across shukr"),
                     p("book", "Tap to read more", "Opens its page in shukr")],
            how: "How to add it", steps: homeSteps)
        case .homeAyah: ShowcaseStory(title: "Daily Ayah", hook: "Keep today's verse with you",
            lead: "Reveal the day's verse in shukr and it stays on your Home Screen, in Arabic and English, so you come back to it through the day.",
            points: [p("eye.slash", "No spoilers", "It waits until you've revealed it"),
                     p("character.book.closed", "Arabic and English", "Side by side")],
            how: "How to add it", steps: homeSteps)
        case .standby: ShowcaseStory(title: "StandBy", hook: "A prayer clock on your nightstand",
            lead: "Charge your iPhone on its side and it becomes a bedside clock, with your prayer ring beside the time.",
            points: [p("bed.double", "From your pillow", "See Fajr's time without picking it up"),
                     p("moon", "Red at night", "iOS dims it in the dark so it won't keep you up")],
            how: "How to set it up", steps: ["Add the Prayer ring to your Home Screen", "Charge your iPhone on its side, locked",
                                             "Swipe to the widgets and pick shukr"])
        // Lock Screen
        case .lockTime: ShowcaseStory(title: "Time left", hook: "A small ring that speaks up when it matters",
            lead: "A circle under your clock with the prayer that's on. In its last hour the name turns into the minutes left, so you notice before it's gone.",
            points: [p("lock", "No unlocking", "There every time you lift your phone"),
                     p("circle.dashed", "Fills as time passes", "The ring follows the prayer's window")]
                     // Only with the Fajr alarm set up (owner: only talk about it then).
                     + (FajrAlarmShown.isOn ? [p("alarm", "Your Fajr alarm", "After Isha it shows when your alarm will ring")] : []),
            how: "How to add it", steps: lockSteps)
        case .lockCountdown: ShowcaseStory(title: "Countdown", hook: "Watch the time tick down",
            lead: "A wider widget under your clock: the prayer that's on, a live timer to its end, and a bar that fills as time passes.",
            points: [p("timer", "To the second", "Hours, minutes and seconds left"),
                     p("arrow.right.circle", "Between prayers",
                       FajrAlarmShown.isOn ? "When the next one starts — or, after Isha, when your Fajr alarm rings" : "When the next one starts")],
            how: "How to add it", steps: lockSteps)
        case .lockName: ShowcaseStory(title: "Above the clock", hook: "One quiet line above the time",
            lead: "A single line over your clock: today's Name of Allah, or the prayer that's on and when it ends.",
            points: [p("textformat", "Fits any Lock Screen", "Just one line, nothing to rearrange")],
            how: "How to add it", steps: ["Touch and hold your Lock Screen, then tap Customize", "Tap the date above the clock", "Pick shukr's line"])
        case .lockControls: ShowcaseStory(title: "Lock Screen buttons", hook: "The qibla, one press from your Lock Screen",
            lead: "Swap a button at the bottom of your Lock Screen for the qibla or your counter.",
            points: [p("location.north.line", "One press", "The qibla map, or straight into counting")],
            how: "How to add it", steps: ["Touch and hold your Lock Screen, then tap Customize", "Tap a button at the bottom, then −", "Tap + and pick a shukr control"])
        // Watch
        case .watchApp: ShowcaseStory(title: "The watch app", hook: "Mark prayers and count zikr without your phone",
            lead: "The same ring as on your phone, on your wrist. Mark a prayer, count zikr, and find the qibla, all without taking your phone out.",
            points: [p("checkmark.circle", "Mark prayers", "Hold the ring; undo if you slip"),
                     p("digitalcrown.horizontal.arrow.clockwise", "Count your way", "Tap, Double Tap or turn the Crown"),
                     p("location.north.line", "The qibla", "Your wrist taps when you face it")],
            how: "How to install it", steps: ["Open the Watch app on your iPhone", "Scroll to Available Apps", "Tap Install next to shukr"])
        case .watchFace: ShowcaseStory(title: "Your watch face", hook: "The prayer's ring, every time you check the time",
            lead: "Put shukr on your watch face and the prayer that's on is there with every glance, its ring filling as the time passes.",
            points: [p("circle.dashed", "Three shapes", "A circle, a wide card or a single line"),
                     p("hand.tap", "Tap it", "Opens shukr on your wrist")],
            how: "How to add it", steps: ["Touch and hold your watch face, then tap Edit", "Swipe to Complications", "Tap a spot and pick shukr"])
        // Hands-free and buttons
        case .siri: ShowcaseStory(title: "Siri", hook: "Mark a prayer without touching your phone",
            lead: "Ask Siri to mark a prayer or tell you the time left.",
            points: [p("checkmark.circle", "“I prayed in shukr”", "Marks it, and tells you how you did"),
                     p("hourglass", "“How long is left in shukr”", "The time left for the prayer that's on")],
            how: "How to use it", steps: ["Say “Hey Siri”, or hold the side button", "Say the phrase, ending in “in shukr”"])
        case .answer: ShowcaseStory(title: "Notification buttons", hook: "Answer the reminder, right where it is",
            lead: "When a prayer's reminder comes in, touch and hold it. Already prayed? Tap it and the prayer is marked and scored. Not yet? Ask to be nudged again in 5 or 10 minutes.",
            points: [p("bell.badge", "It keeps you posted", "Halfway through and with 30 minutes left, until you've marked it"),
                     p("lock", "No opening shukr", "Answer it from the Lock Screen")],
            how: "How to use it", steps: ["When a prayer's notification comes, touch and hold it", "Tap I already prayed, or a nudge"])
        case .controlCenter: ShowcaseStory(title: "Control Center", hook: "shukr a swipe away, from any app",
            lead: "Pull down from your phone's top-right corner for the prayer that's on, or the qibla.",
            points: [p("clock", "The prayer that's on", "And when it ends"),
                     p("location.north.line", "The qibla", "One tap to the map")],
            how: "How to add it", steps: ["Swipe down from the top-right corner", "Tap +, then Add a Control", "Search shukr"])
        case .actionButton: ShowcaseStory(title: "Action button", hook: "The qibla on the side of your phone",
            lead: "Press the button on the side of your iPhone and the qibla opens.",
            points: [p("hand.point.up", "One press, any time", "No unlocking first")],
            how: "How to set it up", steps: ["Open Settings, then Action Button", "Swipe to Controls", "Choose a shukr control"])
        // Around you
        case .prayersMap: ShowcaseStory(title: "Your prayers on the map", hook: "See everywhere you've prayed",
            lead: "Every prayer you mark is pinned where you prayed it and colored by how you did: at home, at work, on the road.",
            points: [p("line.3.horizontal.decrease.circle", "Filter", "By prayer and by dates"),
                     p("mappin", "Tap a pin", "That prayer, when and how you did")],
            action: "Open the map", link: "map")
        case .mosques: ShowcaseStory(title: "Mosques near you", hook: "The nearest masjid, and how to get there",
            lead: "The closest mosques first, with drive and walk times. Look around the entrance before you go, then get directions.",
            points: [p("binoculars", "Look Around", "See the entrance before you go"),
                     p("arrow.triangle.turn.up.right.diamond", "Directions", "Apple Maps or Google Maps"),
                     p("star", "Star yours", "The ones you go to, on top")],
            action: "Find mosques near me", link: "map")
        case .jumuah: ShowcaseStory(title: "Jumu'ah at the masjid", hook: "Friday at the masjid counts as Jumu'ah",
            lead: "Mark Dhuhr at a masjid on a Friday and shukr counts it as Jumu'ah, full marks. It notices the masjid you're at on its own.",
            points: [p("building.columns", "Nothing to set", "shukr knows when you're at a masjid"),
                     p("star", "Your masjid", "Star it to give it its own pin")],
            action: "Find mosques near me", link: "map")
        // Your journey
        case .memories: ShowcaseStory(title: "Moments", hook: "Remember where you prayed",
            lead: "After you mark a prayer, take a photo with both cameras at once: where you are, and you. They're kept day by day, private on your phone.",
            points: [p("lock", "Private", "On your phone and your iCloud backup"),
                     p("magnifyingglass", "Find any", "By prayer, place, note or date"),
                     p("calendar", "On this day", "What you saw a year ago")],
            action: "Open Moments", memories: true)
        case .insights: ShowcaseStory(title: "Journey", hook: "Every prayer you've marked, day by day",
            lead: "Your prayers on one calendar: five dots a day, the days you prayed all five in time lit up, and your streaks. Tap a day to see its prayers, photos and zikr.",
            points: [p("calendar", "The month", "Five dots a day, or a grid of grades"),
                     p("flame", "Streaks", "And the days all in time"),
                     p("photo.stack", "Moments", "Your prayer photos, one tap away")],
            action: "Open Journey", link: "journey")
        // Your zikr
        case .sleep: ShowcaseStory(title: "Sleep mode", hook: "Fall asleep counting, and lose nothing",
            lead: "Counting in bed? Turn on sleep mode: if you drift off, shukr saves your session at your last count and lets your phone lock.",
            points: [p("moon", "Ends on its own", "45 seconds after your last tap"),
                     p("sun.max", "A card in the morning", "Keep counting from where you stopped")],
            how: "How to use it", steps: ["Start a zikr session", "Tap pause", "Turn on the moon"])
        case .tasbihFatimah: ShowcaseStory(title: "Tasbih Fatimah", hook: "33 · 33 · 34, right after you pray",
            lead: "Each time you mark a prayer, shukr offers Tasbih Fatimah. One tap and it counts each phrase for you.",
            points: [p("list.number", "Counts each phrase", "You just keep tapping")],
            action: "Go to Salah", link: "salah")
        case .goals: ShowcaseStory(title: "Daily tasks", hook: "Make your zikr a daily habit",
            lead: "Pick a zikr and a daily task, a count or minutes. Meet it each day and your streak grows.",
            points: [p("flame", "A streak", "Every day you meet it"),
                     p("bell", "A reminder", "If you'd like one")],
            action: "Go to Zikr", link: "zikr")
        // Shortcuts (ShukrAppShortcuts.swift): each tile, its card first. The cards with buttons are iOS 26 (`available`).
        case .siriTimeLeft: tile("Time Left", "How long until it's gone?",
            "A card with the time left in the prayer that's on, and a ✓ to mark it right there. Between sunrise and Dhuhr, it tells you when Dhuhr starts.",
            [p("checkmark.circle", "Mark it from the card", "Tap its ✓"),
             p("button.horizontal.top.press", "On the Action button", "One press, any time")], siri: "“How long is left in shukr”")
        case .siriPrayerTime: tile("Prayer Time", "Any prayer's time, wherever you need it",
            "The next prayer, the current one, or any of the five by name. Build it into your own shortcuts, like lights on before Fajr.",
            [p("checkmark.seal", "Knows you prayed", "Says so first"),
             p("plus.forwardslash.minus", "Before or after", "Minutes either side of a prayer")], siri: "“When is Maghrib in shukr”")
        case .siriTodaysTimes: tile("Today’s Times", "The whole day in one card",
            "All five of today's times: what you've prayed ticked, the prayer that's on highlighted with its time left.",
            [p("circle", "Mark it", "Tap the circle beside the prayer that's on"),
             p("arrow.uturn.backward", "Unmark it", "Tap a ✓ and shukr asks first")], siri: "“Today's prayer times in shukr”")
        case .siriIPrayed: tile("I Prayed", "Mark it without opening shukr",
            "Marks the prayer that's on and shows your score on its card. On the Action button, it's one press after you pray.",
            [p("star", "Scored at that moment", "Just like a tap in the app"),
             p("arrow.uturn.backward", "Undo", "Asks in shukr first, so nothing goes by mistake")], siri: "“I prayed in shukr”")
        case .siriFajrAlarm: tile("Fajr Alarm Time", "When will Fajr's alarm ring?",
            "When your Fajr alarm rings next, shown as the alarm itself. Use it in your own shortcuts, like turning the lights on at that time.",
            [p("alarm", "Even when it's off", "When it would ring")], siri: "“When is my Fajr alarm in shukr”")
        case .siriOpenPage: tile("Open shukr", "Straight to the page you want",
            "Jump right into Salah, Qibla, Zikr, Daily Ayah, the 99 Names or Moments.",
            [p("square.grid.2x2", "A tile for each page", "Pick the one you use most")], siri: "“Open Qibla in shukr”")
        case .siriTasbihFatimah: tile("Open Tasbih Fatimah", "Tasbih Fatimah in one tap",
            "Opens straight into 33 SubhanAllah, 33 Alhamdulillah and 34 Allahu Akbar, counting each phrase for you.",
            [p("list.number", "Counts each phrase", "You just keep tapping")], siri: "“Start Tasbih Fatimah in shukr”")
        case .siriZikrTasks: tile("Zikr Tasks", "Today's zikr, one tap from starting",
            "A card with today's zikr tasks, what's done, and about how long the rest will take. Tap a task and shukr opens counting it.",
            [p("arrow.clockwise", "Picks up where you were", "From today's count")], siri: "“My zikr tasks in shukr”")
        case .siriMosques: tile("Nearby Mosques", "Where's the nearest masjid?",
            "A map and the mosques around you, nearest first, with how far each one is. Tap one and Apple Maps opens with directions.",
            [p("map", "The full map", "Tap the map for shukr's own"),
             p("star", "Yours included", "The mosques you've starred")], siri: "“Nearby mosques in shukr”")
        case .siriPrayedHere: tile("Prayed Here", "Have I prayed here before?",
            "Wherever you are, see how many prayers you've marked there and when you last prayed. At a masjid it counts every prayer marked there.",
            [p("chart.bar", "Each of the five", "A count for each"),
             p("map", "See them on the map", "Every pin where you prayed")], siri: "“Have I prayed here in shukr”")
        // Controls (MoreWidgets.swift): Control Center, a Lock Screen button, or the Action button. Wide or square, a control
        // shows its line of text; small, just its symbol.
        case .ccPrayer: control("Today's Prayers", "When does it end? Just swipe down",
            "The prayer that's on and when it ends (or the next one and when it starts), right in Control Center. Tap it and shukr opens on today's list.",
            [p("clock", "Always current", "“Asr · ends 7:40 PM”"),
             p("list.bullet", "Tap for all five", "Today's list, with what you've marked")])
        case .ccPrayed: control("I Prayed", "Prayed? One tap and it's counted",
            "Tap it after you pray and the prayer that's on is marked and scored for when you prayed it, without opening shukr.",
            [p("checkmark.circle", "It tells you", "“Asr · Mark prayed”, then “Prayed”"),
             p("checkmark.shield", "Never unmarks by accident", "A second tap just says it's done"),
             p("button.horizontal.top.press", "On the Action button", "One press after you pray")])
        case .ccFajrAlarm: control("Fajr Alarm", "Tomorrow's Fajr alarm, on or off in a tap",
            "See when your Fajr alarm rings next, right on the control. Away, or up early anyway? Tap it off, and on again, without digging through Settings.",
            [p("alarm", "When it rings", "“Fajr Alarm · 5:10 AM”"),
             p("arrow.triangle.2.circlepath", "The same alarm", "The one you set up in shukr")])
        case .ccQibla: control("Qibla", "Find the qibla from any app",
            "One tap opens shukr's qibla map, turned so the qibla points up, and your phone buzzes when you face it.",
            [p("apps.iphone", "From anywhere", "Even with another app open"),
             p("button.horizontal.top.press", "Or one press", "Put it on the Action button")])
        case .ccZikr: control("Zikr", "How much zikr is left today?",
            "What's left of today's zikr tasks and about how long it'll take, right in Control Center. Tap it to open your zikr.",
            [p("text.alignleft", "What's left", "“2 tasks left · about 5 min”"),
             p("checkmark.circle", "All done", "It says so when you've finished")])
        }
    }
}

// MARK: - The pictures (drawn like the mockup: the sage panel, the night sky, today's own prayer)

struct ShowcasePicture: View {
    let id: ShowcaseCardID
    /// When the picture appeared: its live arcs are drawn as they stood then (`laStillMoment`).
    @State private var appearedAt = Date()
    var big = false
    /// In the two-by-two grids: a little smaller, as in the mockup.
    var compact = false
    /// Any other size (the grouped page's wide cards).
    var scale: CGFloat? = nil
    /// A list row's small square: a control shows just its circle.
    var thumb = false
    /// An item's page: the Prayers widget plays its taps, and a widget's sizes can be switched.
    var live = false
    /// The size shown, of `families` (owner: one at a time, a toggle for the other).
    @State private var sizeIndex = 0
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The picture sits over the panel and never sizes it (a wide one — a row of tiles — pushed the whole page past
        // the screen's edges).
        background.overlay {
            if thumb, let symbol = controlSymbol {
                CCCircle(symbol: symbol, on: id == .ccFajrAlarm).scaleEffect(1.5)
            } else if onPhone {
                EmptyView()
            } else {
                picture.scaleEffect((scale ?? (big ? 1.7 : compact ? 0.8 : 1)) * fit)
                    .id(sizeIndex)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .identity))
                    .offset(y: families.isEmpty ? 0 : 14)   // under the label row, as the setup's demo card sits under its label
            }
        }
        .overlay(alignment: .top) {
            if onPhone {
                // A list row's small square shows the same phone, smaller (owner: the rows still had the old pictures).
                let s: CGFloat = thumb ? 0.3 : big || live ? 0.55 : compact ? 0.36 : 0.45
                if ExploreItemPhonePicture.ids.contains(id) { ExploreItemPhonePicture(id: id, scale: s) }
                else { ExploreLockPicture(id: id, scale: s) }
            }
        }
        .overlay(alignment: .topLeading) { if !thumb && !families.isEmpty { sizeLabel } }
        .clipped()
        // A still picture: the cards' live arcs and the alarm's shake drawn once, as they stood when it appeared (the Time
        // Left card's window sits round the real now) — perf-recheck: the Shortcuts section sat at ~37 % CPU idle
        // redrawing them.
        .environment(\.laStillMoment, appearedAt)
    }

    /// A Lock Screen item drawn on a phone's Lock Screen; the notification, the map's items and Jumu'ah on the phone too
    /// (owner: "look like our actual app's map"), in a list row's small square too.
    private var onPhone: Bool { [.lockTime, .lockCountdown, .lockName].contains(id) || ExploreItemPhonePicture.ids.contains(id) }

    /// Control Center's grid is wider than the other pictures: drawn at its real size, then fitted.
    private var fit: CGFloat {
        id == .controlCenter ? 0.7 : id == .answer ? 0.42 : id == .standby ? 0.62 : (id == .watchApp || id == .watchFace) ? 0.58 : id.isControl ? 0.8 : id.isSiri ? 0.5 : !families.isEmpty ? (family == .systemSmall ? 0.68 : family == .systemMedium ? 0.55 : 0.36) : 1
    }

    /// The sizes a Home Screen widget comes in (its `supportedFamilies`); empty for everything else.
    private var families: [WidgetFamily] {
        switch id {
        case .homePrayers: [.systemSmall]
        case .homeZikr, .homeName: [.systemSmall, .systemMedium]
        case .homeAyah: [.systemMedium, .systemLarge]
        default: []
        }
    }
    private var family: WidgetFamily { families.isEmpty ? .systemSmall : families[min(sizeIndex, families.count - 1)] }
    private static func sizeName(_ f: WidgetFamily) -> String {
        switch f { case .systemMedium: "Medium"; case .systemLarge: "Large"; default: "Small" }
    }

    /// "Zikr tasks · Small  Medium", as the setup's demo cards label themselves ("Asr · Nudge"): every size it comes in,
    /// the one shown underlined in sage (owner: both shown, the chosen one marked); on an item's page a tap on one shows it.
    private var sizeLabel: some View {
        let switchable = (big || live) && families.count > 1
        return HStack(spacing: 6) {
            Text(id.memberName).fontWeight(.semibold)
            Text("·")
            HStack(spacing: 10) {
                ForEach(Array(families.enumerated()), id: \.offset) { i, f in
                    let on = i == sizeIndex && families.count > 1
                    Button {
                        guard switchable, i != sizeIndex else { return }
                        triggerSomeVibration(type: .light)
                        withAnimation(.easeOut(duration: 0.25)) { sizeIndex = i }
                    } label: {
                        Text(Self.sizeName(f))
                            .fontWeight(on ? .semibold : .regular)
                            .foregroundStyle(on ? Color.sage : Color.primary.opacity(families.count > 1 ? 0.45 : 0.7))
                            .underline(on, color: Color.sage)
                            .padding(.vertical, 6).contentShape(Rectangle())   // a bigger target than the word
                    }
                    .buttonStyle(.plain)
                    .disabled(!switchable)
                    .accessibilityLabel(Self.sizeName(f) + (on ? ", shown" : ""))
                }
            }
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(Color.primary.opacity(0.7))
        .padding(.leading, 16).padding(.top, 6)
    }

    private var controlSymbol: String? { id.isControl ? controls.face(id).symbol : nil }
    private var controls: ControlFaces.Type { ControlFaces.self }

    private var sage: some View {
        LinearGradient(colors: scheme == .dark ? [Color(red: 0.17, green: 0.33, blue: 0.25), Color(red: 0.07, green: 0.10, blue: 0.08)]
                                               : [Color(red: 0.85, green: 0.92, blue: 0.87), Color(red: 0.93, green: 0.96, blue: 0.94)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var night: some View {
        RadialGradient(colors: [Color(red: 0.23, green: 0.31, blue: 0.39), Color(red: 0.08, green: 0.10, blue: 0.11)],
                       center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 260)
    }

    @ViewBuilder private var background: some View {
        switch id {
        case _ where onPhone: sage
        case .lockTime, .lockCountdown, .lockName, .lockControls, .siri, .answer, .controlCenter, .actionButton, .sleep: night
        case _ where id.isControl: night
        case _ where id.isSiri: sage   // the cards as they look in the Shortcuts app
        case .standby: Color.black
        case .prayersMap: MapGrid()
        default: sage
        }
    }

    private var fajrAlarmTime: String {
        ExplorePreset.fajrAlarm
    }

    @ViewBuilder private var picture: some View {
        let p = ShownPrayer.now
        switch id {
        // The real widgets (PrayersWidget.swift / MoreWidgets.swift, in the app's build too — owner: "graphics of our actual
        // widgets"); on an item's page the Prayers widget plays its taps.
        case .homePrayers: RealPrayersWidget(playing: big || live)
        case .homeZikr: RealZikrWidget(family: family)
        case .homeName: RealNameWidget(family: family)
        case .homeAyah: RealAyahWidget(family: family)
        // The real Lock Screen widgets (owner): the Prayers widget's circle and line, and the Name's line above the clock.
        case .lockTime:
            LockClock { RealLockWidget(family: .accessoryCircular) }
        case .lockCountdown:
            LockClock { RealLockWidget(family: .accessoryRectangular) }
        case .lockName:
            LockClock(top: true) {
                NameOfTheDayView(entry: NameOfTheDayEntry(date: Date(), name: NamesOfAllah.nameOfTheDay()), familyOverride: .accessoryInline)
                    .frame(width: 300, height: 20)
                    .environment(\.colorScheme, .dark)
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
            }
        case .lockControls:
            HStack { LockButton(symbol: "location.north.line.fill"); Spacer(); LockButton(symbol: "circle.hexagonpath") }
                .frame(width: 150).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14)
        // The watch's own ring screen and complication (shukrWatchShared: WatchRingFace, PrayerComplicationView), in a
        // watch at its real size (owner: "make the watch ones real too").
        case .watchApp: RealWatch { RealWatchRing() }
        case .watchFace: RealComplications()
        case .standby:
            // The real Prayers widget as StandBy shows it: dark, no background, big beside the clock (owner).
            HStack(spacing: 14) {
                RealPrayersWidget(standby: true)
                Text(ExplorePreset.clockFace).font(.system(size: 76, weight: .light, design: .rounded))
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(Color(red: 1, green: 0.37, blue: 0.27))
            }
        case .siri:
            VStack(spacing: 8) {
                Circle().fill(AngularGradient(colors: [.pink, .indigo, .cyan, .pink], center: .center)).frame(width: 34, height: 34)
                Text("“I prayed in shukr”").font(.system(size: 12, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
        case .answer: RealNotification()
        case .controlCenter:
            // Control Center as iOS lays shukr's five controls out: a grid of 56 pt cells, medium controls two cells wide
            // (a glass capsule: the icon's round badge, then the title and value), small ones a glass circle.
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    CCPill(controls.prayer).gridCellColumns(2)
                    CCCircle(symbol: controls.prayed.symbol)
                    CCCircle(symbol: controls.qibla.symbol)
                }
                GridRow {
                    CCPill(controls.fajr).gridCellColumns(2)
                    CCCircle(symbol: controls.zikr.symbol)
                    Color.clear.frame(width: 56, height: 56)
                }
            }
        case .actionButton:
            ZStack(alignment: .leading) {
                Capsule().fill(Color.orange).frame(width: 6, height: 28).shadow(color: .orange, radius: 6).offset(x: -70, y: -20)
                Label("Qibla", systemImage: "location.north.line.fill").font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
        case .prayersMap:
            ZStack {
                Path { path in path.move(to: CGPoint(x: 70, y: 90)); path.addLine(to: CGPoint(x: 160, y: 30)) }
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                Pin(color: .green).offset(x: -45, y: -8)
                Pin(color: .yellow).offset(x: 15, y: 18)
                Pin(color: .green).offset(x: 30, y: -30)
            }
            .frame(width: 200, height: 120)
        case .jumuah, .mosques:
            VStack(alignment: .leading, spacing: 3) {
                Text(ExplorePreset.masjid).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(id == .mosques ? "1.2 mi · 4 min drive" : "Friday, 1:15 PM").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
                Label("Jumu'ah counts here", systemImage: "checkmark.seal.fill").font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sage)
            }
            .padding(10).frame(width: 172, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        case .memories:
            ZStack {
                PhotoCard(colors: [Color(red: 0.79, green: 0.64, blue: 0.42), Color(red: 0.42, green: 0.31, blue: 0.18)]).rotationEffect(.degrees(-9)).offset(x: -10, y: 4)
                PhotoCard(colors: [Color(red: 0.50, green: 0.66, blue: 0.79), Color(red: 0.18, green: 0.31, blue: 0.42)]).rotationEffect(.degrees(6)).offset(x: 8, y: -2)
                PhotoCard(colors: [Color(red: 0.62, green: 0.78, blue: 0.66), Color(red: 0.24, green: 0.42, blue: 0.30)])
            }
        case .insights:
            HStack(spacing: 7) {
                MiniArc(progress: 0.86).frame(width: 40, height: 40)
                MiniArc(progress: 0.64, color: .yellow).frame(width: 40, height: 40)
                MiniArc(progress: 0.92).frame(width: 40, height: 40)
            }
        case .sleep:
            Image(systemName: "moon.fill").font(.system(size: 40)).foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.78))
        case .tasbihFatimah:
            Text("33 · 33 · 34").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.primary.opacity(0.85))
        // The real cards (SharedTargetForIntents.swift, PlaceShortcuts.swift) in a Shortcuts sheet, or the tile for an action
        // without one (owner: "show the tile or the intent recipe or the card").
        case .siriTimeLeft:
            ShortcutSheetShot(dialog: "\(p.left) left for \(p.name).") {
                // The card's time left and ring tick from the clock: the same window moved round the real now, with the
                // preset's end written under it.
                let shift = Date().timeIntervalSince(ExplorePreset.now)
                PrayerCardSnippet(state: .init(label: p.name, start: p.start.addingTimeInterval(shift), end: p.end.addingTimeInterval(shift),
                                               symbol: prayerIcon(for: p.name), dark: scheme == .dark))
                    .environment(\.laShownEnd, p.end)
            }
        case .siriPrayerTime:
            // The next prayer, as Prayer Time → Next answers it.
            let next = ExplorePreset.windows["Maghrib"]!.start
            ShortcutSheetShot(dialog: "Maghrib is at \(shortTimePM(next)).") {
                NextPrayerSnippet(name: "Maghrib", start: next, now: ExplorePreset.now)
            }
        case .siriTodaysTimes:
            ShortcutSheetShot(dialog: "\(p.name) is on until \(shortTimePM(p.end)).") { TodaysTimesSnippet(rows: ExplorePreset.todaysTimes, markable: true, now: ExplorePreset.now) }
        case .siriIPrayed:
            ShortcutSheetShot(dialog: "\(p.name) marked as prayed. Perfect.") {
                PrayerCardSnippet(state: .init(label: p.name, start: p.start, end: p.end, symbol: prayerIcon(for: p.name),
                                               markedAt: p.start.addingTimeInterval(12 * 60), dark: scheme == .dark), action: .undo)
            }
        case .siriFajrAlarm:
            ShortcutSheetShot(dialog: "Your Fajr alarm is at \(fajrAlarmTime).") {
                ShortcutCards.fajrAlarm?(false, Date().addingTimeInterval(86400)) ?? AnyView(EmptyView())
            }
        case .siriOpenPage:
            ShortcutTiles(tiles: [("sun.horizon", "Salah"), ("location.north.line", "Qibla"), ("hands.and.sparkles", "Zikr"), ("book", "Daily Ayah")])
        case .siriTasbihFatimah:
            ShortcutTiles(tiles: [("circle.hexagonpath", "Open Tasbih Fatimah")])
        case .siriZikrTasks:
            let tasks = ShowcaseSamples.zikrTasks
            ShortcutSheetShot(dialog: ZikrTasksSnippet.spoken(tasks)) { ZikrTasksSnippet(tasks: tasks) }
        case .siriMosques:
            ShortcutSheetShot(dialog: NearbyMosquesSearch.spoken(ShowcaseSamples.mosques)) {
                NearbyMosquesSnippet(outcome: ShowcaseSamples.mosques, map: ShowcaseSamples.fakeMap(dark: scheme == .dark))
            }
        case .siriPrayedHere:
            let here = ShowcaseSamples.prayedHere
            ShortcutSheetShot(dialog: here.spoken) { PrayedHereSnippet(summary: here) }
        // Each control as iOS draws it, wide and small, from the control's own values (ControlFaces).
        case .ccPrayer, .ccPrayed, .ccFajrAlarm, .ccQibla, .ccZikr:
            let f = controls.face(id)
            HStack(spacing: 12) { CCPill(f); CCCircle(symbol: f.symbol, on: f.on) }
        case .goals:
            HStack(spacing: 10) {
                MiniArc(progress: 1).frame(width: 44, height: 44)
                MiniArc(progress: 0.6).frame(width: 44, height: 44)
                Image(systemName: "flame.fill").font(.title2).foregroundStyle(Color.sage)
            }
        }
    }
}

// Picture pieces.

/// A medium control in Control Center: a glass capsule, the icon in its own round badge on the left (lit white when a
/// toggle is on), then the title and its value.
struct CCPill: View {
    let symbol: String
    let title: String
    let value: String?
    var on = false
    init(symbol: String, title: String, value: String?, on: Bool = false) { self.symbol = symbol; self.title = title; self.value = value; self.on = on }
    init(_ f: ControlFace) { self.init(symbol: f.symbol, title: f.title, value: f.line, on: f.on) }
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Color.black : Color.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(on ? Color.white : Color.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let value { Text(value).font(.system(size: 11)).opacity(0.7) }
            }
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10).padding(.trailing, 8)
        .frame(width: 124, height: 56)
        .background(Capsule().fill(.white.opacity(0.16)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// A small control in Control Center: a glass circle with the icon (filled white when a toggle is on).
struct CCCircle: View {
    let symbol: String
    var on = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(on ? Color.black : Color.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(on ? Color.white : Color.white.opacity(0.16)))
            .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// You ask, Siri answers with a card (the phrase's own words; the answer shaped like the shortcut's).
/// The Prayers widget itself, at a small widget's size, on Explore's preset day (`ExplorePreset`). `playing` (its item's
/// page) makes it the one picture in Explore you can play with (owner: "allow just this graphic the special ability to be
/// interactive so the user can demo it"): every button does what the real one does on the preset day — the ring flips
/// ends-at ⇄ time left, ✓ marks Asr (the ring moves on to Maghrib), the arrow opens today's times and back, a corner says
/// where it would open shukr — nothing saved; "Start over" puts it back. The widget's own buttons never get the touch
/// (they'd really run): one layer over it takes every tap and works out which button it was on.
struct RealPrayersWidget: View {
    var playing = false
    /// StandBy: the widget's dark style on black, no container (as iOS shows widgets there).
    var standby = false
    /// A style to show (Settings → Appearance → Prayers widget's preview); nil = the widget's default.
    var style: WidgetStyle? = nil
    @State private var entry: PrayersWidgetEntry?
    @State private var first: PrayersWidgetEntry?
    @State private var touch: UnitPoint?
    @State private var touches = 0
    /// What a corner would open, said under the widget for a moment.
    @State private var note: String?
    @State private var notes = 0
    @Environment(\.colorScheme) private var scheme
    static let side: CGFloat = 170

    var body: some View {
        ZStack {
            // No padding: the widget turns its content margins off (contentMarginsDisabled), so its view fills the widget —
            // padded here, its corner buttons sat in on the ring (owner).
            if let entry { PrayersWidgetView(entry: entry) }
        }
        .frame(width: Self.side, height: Self.side)
        .background(standby ? Color.black : (entry?.background ?? WidgetSoft.surface(scheme)))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            GeometryReader { g in
                if let touch {
                    Circle().fill(Color.white.opacity(0.55)).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(Color.black.opacity(0.08)))
                        .position(x: touch.x * g.size.width, y: touch.y * g.size.height)
                        .id(touches)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
        }
        .overlay {
            if playing {
                Color.clear.contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .onTapGesture(coordinateSpace: .local) { press($0) }
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) { if playing { footer.offset(y: 21) } }
        .shadow(color: .black.opacity(standby ? 0 : 0.15), radius: 10, y: 5)
        .environment(\.colorScheme, standby ? .dark : scheme)
        .allowsHitTesting(playing)
        .task(id: style) { start() }
    }

    private func start() {
        var e = ExplorePreset.prayersEntry()
        if let style { e.style = style }
        if standby { e.style = .dark }
        first = e
        entry = e
    }

    /// Under the widget: a hint until it's been played with, then what a corner would do, or Start over.
    private var footer: some View {
        Group {
            if let note {
                Text(note).id(notes)
            } else if let entry, let first, !Self.same(entry, first) {
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.35)) { self.entry = first }
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise").padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.sage)
            } else {
                Text("Try it: tap the ring, the ✓ or the arrow")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(Color.primary.opacity(0.6))
        .fixedSize()
        .transition(.opacity)
    }

    private static func same(_ a: PrayersWidgetEntry, _ b: PrayersWidgetEntry) -> Bool {
        a.textToggle == b.textToggle && a.toggleShowAllTImes == b.toggleShowAllTImes && a.completedToday == b.completedToday
    }

    /// A tap on the widget: which of its buttons it was on (the widget's own layout, no margins: its buttons 6 pt in,
    /// 30 pt targets — the check top left, the corners and the arrow along the bottom, the ring in the middle).
    private func press(_ at: CGPoint) {
        guard var e = entry else { return }
        let side = Self.side, inset: CGFloat = 6, target: CGFloat = 30
        let bottom = at.y > side - inset - target - 6
        let left = at.x < inset + target + 6, right = at.x > side - inset - target - 6
        let middle = abs(at.x - side / 2) < target / 2 + 8
        func show(_ change: () -> Void) {
            touches += 1
            withAnimation(.easeOut(duration: 0.15)) { touch = UnitPoint(x: at.x / side, y: at.y / side) }
            triggerSomeVibration(type: .light)
            withAnimation(.easeInOut(duration: 0.35)) { change() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.2))
                withAnimation(.easeOut(duration: 0.3)) { touch = nil }
            }
        }
        if e.toggleShowAllTImes {
            // Today's times: the arrow goes back to the ring; a row that has started marks it, or unmarks it if it's
            // marked (owner: in the demo just do it — the real widget opens shukr to ask "Unmark …?"). The rows share
            // the list's height as TimesListView lays them out: 10 pt in, the place's line, then six rows above the
            // arrow's 30 pt.
            if bottom && middle { show { entry = e.at(e.date, list: false) } ; return }
            let order = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
            let top: CGFloat = 23, rowHeight = min(22, (side - top - WidgetChevronButtonReserved) / CGFloat(order.count))
            let i = Int(floor((at.y - top) / rowHeight))
            guard order.indices.contains(i), at.y >= top, order[i] != "Sunrise",
                  let window = e.prayerDict[order[i]], window.start <= e.date else { return }
            let name = order[i]
            show {
                if e.completedScores[name] != nil {
                    e.completedScores[name] = nil
                } else {
                    e.completedScores[name] = PrayerScoring.score(start: window.start, end: window.end, markedAt: ExplorePreset.now)
                }
                entry = e
            }
            return
        }
        if bottom && middle {
            show { entry = e.at(e.date, list: true) }
        } else if bottom && (left || right) {
            let corner = left ? e.leftCorner : e.rightCorner
            guard let name = Self.opens(corner) else { return }
            show {}
            say("Opens shukr on \(name)")
        } else if !bottom && right && at.y < inset + target + 6 {
            // The camera, once Asr is marked: it would open shukr's camera for Asr's photo.
            guard e.completedScores[ExplorePreset.prayer] != nil else { return }
            show {}
            say("Opens shukr's camera for a photo of \(ExplorePreset.prayer)")
        } else if !bottom && left && at.y < inset + target + 6 {
            // ✓: Asr marked at the preset moment, scored as the app would; the ring moves on to the next prayer.
            let asr = ExplorePreset.asr
            guard e.completedScores[ExplorePreset.prayer] == nil else { return }
            show {
                e.completedScores[ExplorePreset.prayer] = PrayerScoring.score(start: asr.start, end: asr.end, markedAt: ExplorePreset.now)
                entry = e
            }
        } else if hypot(at.x - side / 2, at.y - side / 2) < 52 {
            show { entry = e.with(text: !e.textToggle) }
        }
    }

    /// The list's room kept for its arrow (PrayersWidgetView.WidgetChevronButton.reserved).
    private var WidgetChevronButtonReserved: CGFloat { PrayersWidgetView.WidgetChevronButton.reserved }

    private static func opens(_ corner: WidgetCornerAction) -> String? {
        switch corner {
        case .qibla: "the qibla"
        case .tasbeeh: "a tasbih"
        case .dailyAyah: "the Daily Ayah"
        case .names: "the 99 Names"
        case .none: nil
        }
    }

    private func say(_ text: String) {
        notes += 1
        let mine = notes
        withAnimation(.easeOut(duration: 0.2)) { note = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if notes == mine { withAnimation(.easeOut(duration: 0.3)) { note = nil } }
        }
    }
}

extension PrayersWidgetEntry {
    /// The same entry with the ring's text side flipped (the widget's own tap).
    func with(text: Bool) -> PrayersWidgetEntry {
        var e = PrayersWidgetEntry(date: date, heading: heading, latitude: latitude, longitude: longitude,
                           toggleShowAllTImes: toggleShowAllTImes, prayerDict: prayerDict,
                           todayPrayerTimes: todayPrayerTimes, locationName: locationName, textToggle: text,
                           completedScores: completedScores, nextFajr: nextFajr, nextSunrise: nextSunrise,
                           leftCorner: leftCorner, rightCorner: rightCorner, scoreColors: scoreColors,
                           ringAbove: ringAbove, style: style)
        return e
    }
}

/// A real widget's view at one size, on its own background, never taking a touch (its buttons would really run).
private struct SizedWidget<Content: View, Background: View>: View {
    let family: WidgetFamily
    @ViewBuilder let content: () -> Content
    @ViewBuilder let background: () -> Background
    static func size(_ f: WidgetFamily) -> CGSize {
        let s = RealPrayersWidget.side
        switch f {
        case .systemMedium: return CGSize(width: s * 2 + 18, height: s)
        case .systemLarge: return CGSize(width: s * 2 + 18, height: s * 2 + 18)
        default: return CGSize(width: s, height: s)
        }
    }
    var body: some View {
        let size = Self.size(family)
        content()
            .padding(14)
            .frame(width: size.width, height: size.height)
            .background(background())
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
            .allowsHitTesting(false)
    }
}

/// The day every Explore picture shows, the same for everyone (owner: "show us what the actual thing will look like
/// visually, not necessarily personalized" — and nobody's pictures half empty without a location, tasks or a masjid):
/// today at fixed, typical times (owner: each prayer at a time that makes sense for it), seen at 5:50 PM — Asr an hour
/// in (still on time, the ring yellow; later it turns red), Fajr and Dhuhr prayed, two zikr tasks to do, the alarm on. Nothing is read from the phone, so
/// nothing loads. The real views draw from this `now` where they'd read the clock (`LiveArc.staticNow`, set in
/// App.init; the watch's views take it as their entry's date / `now`).
enum ExplorePreset {
    static let prayer = "Asr"
    static let city = "Chicago"
    static let masjid = "Masjid Al-Noor"
    /// Fajr on time, Dhuhr perfect.
    static let scores: [String: Double] = ["Fajr": 0.88, "Dhuhr": 1]

    private static func today(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
    /// The moment the pictures show.
    static var now: Date { today(17, 50) }
    /// Today's windows (Sunrise too, as the widget keeps it).
    static var windows: [String: (start: Date, end: Date)] {
        ["Fajr": (today(5, 30), today(6, 50)), "Sunrise": (today(6, 50), today(13, 10)), "Dhuhr": (today(13, 10), today(16, 50)),
         "Asr": (today(16, 50), today(19, 40)), "Maghrib": (today(19, 40), today(21, 5)), "Isha": (today(21, 5), today(23, 59))]
    }
    static var asr: (start: Date, end: Date) { windows[prayer]! }
    static var fajrAlarm: String { shortTimePM(today(5, 10)) }   // 20 minutes before Fajr
    /// The Lock Screen / StandBy clock at that moment: "5:50".
    static var clockFace: String { clockFace(at: now) }
    static func clockFace(at date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        f.amSymbol = ""; f.pmSymbol = ""
        return f.string(from: date).trimmingCharacters(in: .whitespaces)
    }

    /// The Lock Screen widget's entry at a playing state (LockDemoStep); none = the preset moment.
    static func lockEntry(_ step: LockDemoStep?) -> PrayersWidgetEntry {
        let base = prayersEntry()
        guard let step else { return base }
        var e = base.at(step.date, list: false)
        if step.asrMarked { e.completedScores[prayer] = PrayerScoring.score(start: asr.start, end: asr.end, markedAt: asr.end.addingTimeInterval(-25 * 60)) }
        return e
    }

    /// The Prayers widget's entry for that day (the widget's own view draws it).
    static func prayersEntry() -> PrayersWidgetEntry {
        let w = windows
        let fajr = w["Fajr"]!
        var e = PrayersWidgetEntry(date: now, heading: 0, latitude: 0, longitude: 0, toggleShowAllTImes: false,
                                  prayerDict: w.mapValues { (start: $0.start, end: $0.end, window: $0.end.timeIntervalSince($0.start)) },
                                  todayPrayerTimes: PrayerUtils.dummyPrayerTimes(), locationName: city, textToggle: false,
                                  completedScores: scores,
                                  nextFajr: fajr.start.addingTimeInterval(86_400), nextSunrise: fajr.end.addingTimeInterval(86_400))
        return e
    }

    /// Today's Times' rows for that day.
    static var todaysTimes: [TodaysTimesSnippet.Row] {
        let w = windows
        return ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].map { name in
            let (start, end) = w[name]!
            return .init(name: name, start: start, end: end, marked: scores[name] != nil,
                         when: end <= now ? .earlier : start <= now ? .now : .coming)
        }
    }

    static let zikrTasks: [ZikrTaskSnapshot] = [
        ZikrTaskSnapshot(id: "1", name: "Subhanallah", isCountMode: true, goal: 100, count: 40, minutes: 0, done: false, secondsLeft: 120),
        ZikrTaskSnapshot(id: "2", name: "Astaghfirullah", isCountMode: true, goal: 100, count: 0, minutes: 0, done: false, secondsLeft: 200),
        ZikrTaskSnapshot(id: "3", name: "Alhamdulillah", isCountMode: true, goal: 33, count: 33, minutes: 0, done: true)]
}

/// The five controls' faces on that day, each through its control's own `face` where it has one (the words stay the
/// control's), in the state that shows what it does (owner: Fajr Alarm on, with when it rings).
enum ControlFaces {
    static var prayer: ControlFace {
        ControlFace(symbol: prayerIcon(for: ExplorePreset.prayer), title: ExplorePreset.prayer, line: "ends \(shortTimePM(ExplorePreset.asr.end))")
    }
    static var prayed: ControlFace { PrayedControl.Value(name: ExplorePreset.prayer, marked: false, none: false).face }
    static var fajr: ControlFace { FajrAlarmControl.Value(on: true, time: ExplorePreset.fajrAlarm).face }
    static let qibla = ControlFace(symbol: "location.north.line.fill", title: "Qibla", line: nil)
    static var zikr: ControlFace {
        let left = ExplorePreset.zikrTasks.filter { !$0.done }
        let minutes = zikrEstimateString(left.compactMap(\.secondsLeft).reduce(0, +)).replacingOccurrences(of: "~", with: "")
        return ControlFace(symbol: "hands.and.sparkles", title: "Zikr", line: "\(left.count) tasks left · about \(minutes)")
    }

    static func face(_ id: ShowcaseCardID) -> ControlFace {
        switch id {
        case .ccPrayer: prayer
        case .ccPrayed: prayed
        case .ccFajrAlarm: fajr
        case .ccZikr: zikr
        default: qibla
        }
    }
}

/// A prayer notification held open, as iOS shows it: the scheduler's own halfway notification for the prayer that's on
/// (NotificationScheduler.prayerNotification — the words your phone gets), and its buttons (ActionTitle).
struct RealNotification: View {
    var body: some View {
        let p = ShownPrayer.now
        let window = (start: p.start, end: p.end, window: p.end.timeIntervalSince(p.start))
        let sent = NotificationScheduler.prayerNotification("Mid", prayer: p.name, window: window)
            ?? NotificationScheduler.prayerNotification("Start", prayer: p.name, window: window)
        VStack(spacing: 8) {
            if let (at, content) = sent {
                NotificationBanner(title: content.title, subtitle: content.subtitle, line: content.body, at: at)
            }
            VStack(spacing: 0) {
                ForEach([NotificationScheduler.ActionTitle.prayed, NotificationScheduler.ActionTitle.nudge5,
                         NotificationScheduler.ActionTitle.nudge10], id: \.self) { title in
                    if title != NotificationScheduler.ActionTitle.prayed { Divider() }
                    Text(title).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 30)
        }
        .frame(width: 340)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .light)   // the light notification, whatever the phone's look (owner)
    }
}

/// A watch at its real size (46 mm: a 208 × 248 pt screen in its case), the screen whatever's given.
struct RealWatch<Screen: View>: View {
    @ViewBuilder let screen: () -> Screen
    var body: some View {
        screen()
            .frame(width: 208, height: 248)
            .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 62, style: .continuous).fill(Color(white: 0.13)))
            .overlay(alignment: .trailing) {
                Capsule().fill(Color(white: 0.2)).frame(width: 9, height: 46).offset(x: 6, y: -40)   // the Crown
            }
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .allowsHitTesting(false)
    }
}

/// The watch's Salah page: its page colour and its ring (WatchRingFace) on the prayer that's on, or the next.
private struct RealWatchRing: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = ShownPrayer.now
        ZStack {
            WatchNeu.page(scheme)
            WatchRingFace(prayer: WatchPrayer(name: p.name, start: p.start, end: p.end), current: p.isOn, now: ExplorePreset.now, k: 1.1)
                .frame(width: 140, height: 140)
        }
    }
}

/// shukr's watch complications on their own, as a face shows them (owner: "without the watch being there … all the
/// different complications"): the circle, the line and the inline, each PrayerComplicationView at its size. (The corner
/// is watchOS-only code.)
private struct RealComplications: View {
    var body: some View {
        let p = ShownPrayer.now
        let entry = PrayerComplicationEntry(date: ExplorePreset.now, prayer: WatchPrayer(name: p.name, start: p.start, end: p.end), current: p.isOn)
        // Each its own piece (owner: "shouldn't they be separate objects?"), on black as a watch face shows it.
        HStack(alignment: .center, spacing: 18) {
            face(entry, .accessoryCircular)
                .frame(width: 64, height: 64)
                .padding(8)
                .background(Circle().fill(Color.black))
            VStack(alignment: .leading, spacing: 16) {
                face(entry, .accessoryRectangular)
                    .frame(width: 170, height: 64, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black))
                face(entry, .accessoryInline)
                    .frame(height: 18, alignment: .leading)
                    .fixedSize()
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black))
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private func face(_ entry: PrayerComplicationEntry, _ family: WidgetFamily) -> some View {
        PrayerComplicationView(entry: entry, familyOverride: family)
    }
}

/// The Prayers widget's own Lock Screen view (circle or line), on the preset day, white on the Lock Screen's dark as iOS
/// draws it there; never taking a touch.
struct RealLockWidget: View {
    let family: WidgetFamily
    /// The state Explore's Lock Screen picture is playing (LockDemoPlayer); none = the preset moment.
    @Environment(\.lockDemoStep) private var step
    private var size: CGSize {
        switch family {
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        default: CGSize(width: 240, height: 20)
        }
    }
    var body: some View {
        PrayerLockScreenView(entry: ExplorePreset.lockEntry(step), family: family)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .tint(.white)   // iOS draws Lock Screen widgets in one tint; outside it the bar came out blue
            .allowsHitTesting(false)
    }
}

/// One state of the Lock Screen widget in Explore's picture (owner, 2026-10-15: "a motion graphic that shows all of the
/// states"): a moment of the preset day, and whether Asr is marked by then.
struct LockDemoStep: Equatable {
    let date: Date
    let asrMarked: Bool
    /// In turn: Asr filling · its last hour ("27m left") · Asr marked, the next prayer dashed · and only with the Fajr
    /// alarm set up (owner: only then talk about it), after Isha — when the alarm rings.
    static var all: [LockDemoStep] {
        let asr = ExplorePreset.asr, cal = Calendar.current
        var steps = [LockDemoStep(date: ExplorePreset.now, asrMarked: false),
                     LockDemoStep(date: asr.end.addingTimeInterval(-27 * 60), asrMarked: false),
                     LockDemoStep(date: asr.end.addingTimeInterval(-20 * 60), asrMarked: true)]
        if FajrAlarmShown.isOn,
           let night = cal.date(byAdding: .minute, value: 30, to: cal.startOfDay(for: ExplorePreset.now.addingTimeInterval(86_400))) {
            steps.append(LockDemoStep(date: night, asrMarked: true))
        }
        return steps
    }
}
private struct LockDemoStepKey: EnvironmentKey { static let defaultValue: LockDemoStep? = nil }
extension EnvironmentValues {
    var lockDemoStep: LockDemoStep? {
        get { self[LockDemoStepKey.self] }
        set { self[LockDemoStepKey.self] = newValue }
    }
}

/// Plays `LockDemoStep.all` over a Lock Screen picture, one state every 2.4 s (the last held a little longer) — the
/// setup's notification demo's way: a task tied to the view (off screen it stops), discrete steps, no per-frame timer;
/// Reduce Motion: the first state, still. The clock and every widget in the picture read the same step.
struct LockDemoPlayer: ViewModifier {
    @State private var i = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        let steps = LockDemoStep.all
        content
            .environment(\.lockDemoStep, steps[min(i, steps.count - 1)])
            .task {
                guard !reduceMotion, steps.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(i == steps.count - 1 ? 3.2 : 2.4))
                    if Task.isCancelled { break }
                    withAnimation(.easeInOut(duration: 0.35)) { i = (i + 1) % steps.count }
                }
            }
    }
}
extension View {
    /// Explore's Lock Screen pictures: the widget's states in turn (LockDemoPlayer).
    func playsLockStates() -> some View { modifier(LockDemoPlayer()) }
}

/// The clock on Explore's Lock Screen pictures, at the state playing.
struct LockDemoClock: View {
    @Environment(\.lockDemoStep) private var step
    var body: some View { Text(ExplorePreset.clockFace(at: step?.date ?? ExplorePreset.now)).contentTransition(.numericText()) }
}

/// The Zikr widget itself at one size, with the preset day's tasks.
struct RealZikrWidget: View {
    var family: WidgetFamily = .systemSmall
    var body: some View {
        SizedWidget(family: family) {
            ZikrTasksWidgetView(entry: ZikrTasksEntry(date: Date(), tasks: ShowcaseSamples.zikrTasks, storeReady: true), familyOverride: family)
        } background: { Color("widgetBgColor") }
    }
}

/// The Name of the Day widget itself at one size, today's Name.
struct RealNameWidget: View {
    var family: WidgetFamily = .systemSmall
    var body: some View {
        SizedWidget(family: family) {
            NameOfTheDayView(entry: NameOfTheDayEntry(date: Date(), name: NamesOfAllah.nameOfTheDay()), familyOverride: family)
        } background: { BrandBackground() }
        .environment(\.colorScheme, .dark)   // the widget is dark only (owner)
    }
}

/// The Daily Ayah widget itself at one size, with the widget's own sample verse (never today's: no spoiled reveal).
struct RealAyahWidget: View {
    var family: WidgetFamily = .systemMedium
    var body: some View {
        SizedWidget(family: family) {
            DailyAyahWidgetView(entry: DailyAyahEntry(date: Date(),
                                                      ayah: DailyAyahProvider.sample),
                                familyOverride: family)
        } background: { BrandBackground() }
        .environment(\.colorScheme, .dark)   // the widget is dark only (owner)
    }
}

/// A Shortcuts card as the Shortcuts app shows it: the spoken line, a rule, the card; drawn at its real width, top kept.
private struct ShortcutSheetShot<Card: View>: View {
    let dialog: String
    @ViewBuilder let card: () -> Card
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dialog)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 12)
            Divider()
            card()
        }
        .frame(width: 360, height: 320, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(.systemBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .offset(y: 40)   // the top of the sheet in view; the rest runs off the panel's foot
    }
}

/// Tiles as the Shortcuts app lays shukr's out: a round badge with the symbol in sage, the name under it.
private struct ShortcutTiles: View {
    let tiles: [(String, String)]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(120), spacing: 18), count: min(tiles.count, 2)), spacing: 16) {
            ForEach(tiles, id: \.1) { t in
                VStack(spacing: 8) {
                    Image(systemName: t.0)
                        .font(.system(size: 30))
                        .foregroundStyle(Color.sage)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
                    Text(t.1).font(.system(size: 17)).multilineTextAlignment(.center).frame(width: 110)
                }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color(.systemGroupedBackground).opacity(0.85)))
    }
}

/// The preset day's cards (ExplorePreset): the same for everyone.
@MainActor enum ShowcaseSamples {
    static var zikrTasks: [ZikrTaskSnapshot] { ExplorePreset.zikrTasks }
    static var mosques: NearbyMosquesSearch.Outcome {
        let here = CLLocation(latitude: 0, longitude: 0)
        let names = [ExplorePreset.masjid, "Islamic Center", "Masjid Ar-Rahman"]
        let list = names.prefix(3).enumerated().map { i, n in
            NearbyMosque(name: n, coordinate: here.coordinate, meters: [1_900, 3_200, 4_300][i], address: nil)
        }
        return .found(here: here, Array(list))
    }
    /// A drawn stand-in for the Nearby Mosques card's map strip (owner: "add a fake map"): land, a park, water, roads,
    /// a highway, three sage pins (the nearest larger) and the blue dot — the real card's snapshot needs a location.
    static func fakeMap(dark: Bool) -> UIImage {
        let size = CGSize(width: 360, height: 110)
        func c(_ light: UInt32, _ night: UInt32) -> UIColor {
            let v = dark ? night : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            c(0xF2EFE9, 0x2B2D31).setFill(); g.fill(CGRect(origin: .zero, size: size))
            c(0xCDE8C4, 0x2F3E33).setFill()
            UIBezierPath(roundedRect: CGRect(x: 30, y: 10, width: 70, height: 40), cornerRadius: 14).fill()
            UIBezierPath(roundedRect: CGRect(x: 250, y: 66, width: 60, height: 34), cornerRadius: 12).fill()
            let water = UIBezierPath()
            water.move(to: CGPoint(x: 360, y: 0)); water.addCurve(to: CGPoint(x: 300, y: 40), controlPoint1: CGPoint(x: 330, y: 8), controlPoint2: CGPoint(x: 312, y: 22))
            water.addCurve(to: CGPoint(x: 360, y: 60), controlPoint1: CGPoint(x: 296, y: 52), controlPoint2: CGPoint(x: 330, y: 58))
            water.close(); c(0xAAD3F2, 0x1F3348).setFill(); water.fill()
            func road(_ pts: [CGPoint], _ w: CGFloat, _ color: UIColor) {
                let p = UIBezierPath(); p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
                p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; color.setStroke(); p.stroke()
            }
            let street = c(0xFFFFFF, 0x45474D)
            road([CGPoint(x: 0, y: 70), CGPoint(x: 140, y: 64), CGPoint(x: 360, y: 82)], 4, street)
            road([CGPoint(x: 120, y: 0), CGPoint(x: 128, y: 110)], 4, street)
            road([CGPoint(x: 210, y: 0), CGPoint(x: 196, y: 110)], 3, street)
            road([CGPoint(x: 0, y: 28), CGPoint(x: 360, y: 20)], 3, street)
            road([CGPoint(x: 0, y: 100), CGPoint(x: 90, y: 40), CGPoint(x: 260, y: 0)], 6, c(0xF6D98B, 0x5A5240))
            let sage = UIColor(red: 0.40, green: 0.64, blue: 0.50, alpha: 1)
            func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ fill: UIColor, ring: CGFloat) {
                UIColor.white.setFill(); UIBezierPath(ovalIn: CGRect(x: x - r - ring, y: y - r - ring, width: 2 * (r + ring), height: 2 * (r + ring))).fill()
                fill.setFill(); UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
            }
            dot(240, 44, 5, sage, ring: 2)
            dot(82, 86, 5, sage, ring: 2)
            dot(160, 40, 7, sage, ring: 2)
            dot(146, 60, 5, .systemBlue, ring: 2.5)
        }
    }

    static var prayedHere: PrayedHere {
        var s = PrayedHere(here: CLLocation(latitude: 0, longitude: 0))
        s.place = ExplorePreset.masjid
        s.atMasjid = true
        s.count = 12
        s.last = ("Asr", Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        s.perPrayer = ["Fajr": 1, "Dhuhr": 4, "Asr": 3, "Maghrib": 3, "Isha": 1]
        return s
    }
}

private struct SiriExchange: View {
    let ask: String
    let answer: String
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(AngularGradient(colors: [.pink, .indigo, .cyan, .pink], center: .center)).frame(width: 26, height: 26)
                Text("“\(ask)”").font(.system(size: 12, design: .rounded)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(answer)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.11, green: 0.13, blue: 0.15))
                .lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(width: 190)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.94)))
        }
    }
}

private struct WidgetTile<Content: View>: View {
    var fill: Color = .white
    var width: CGFloat = 96, height: CGFloat = 96
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .frame(width: width, height: height)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .environment(\.colorScheme, .light)
    }
}

private struct RingFace: View {
    let name: String
    let line: String?
    let progress: Double
    let size: CGFloat
    var dark = false
    var body: some View {
        ZStack {
            Circle().stroke(dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08), lineWidth: size * 0.1)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(name).font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                if let line { Text(line).font(.system(size: size * 0.14, design: .rounded)).opacity(0.6) }
            }
            .foregroundStyle(dark ? Color.white : Color.black)
        }
        .frame(width: size, height: size)
    }
}

private struct MiniArc: View {
    let progress: Double
    var color: Color = .green
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: 5)
            Circle().trim(from: 0, to: progress).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

private struct ZikrRow: View {
    let name: String
    let fill: Double
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.1), lineWidth: 2.5)
                Circle().trim(from: 0, to: fill).stroke(Color.green, lineWidth: 2.5).rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)
            Text(name).font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(.black).lineLimit(1)
        }
    }
}

private struct LockClock<Accessory: View>: View {
    var top = false
    @ViewBuilder let accessory: () -> Accessory
    var body: some View {
        VStack(spacing: 6) {
            if top { accessory() }
            Group {
                if top { Text(ExplorePreset.clockFace) } else { LockDemoClock() }
            }
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            if !top { accessory() }
        }
        .foregroundStyle(.white)
        .playsLockStates()
    }
}

private struct LockCircle: View {
    let text: String
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: 0.75).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            Text(text).font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .frame(width: 44, height: 44)
    }
}

private struct LockButton: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.18)))
    }
}

private struct CCTile: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.18)))
    }
}

private struct WatchCase<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .frame(width: 76, height: 92)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color(white: 0.2), lineWidth: 4))
    }
}

private struct Pin: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2)).shadow(radius: 2)
    }
}

private struct PhotoCard: View {
    let colors: [Color]
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 82, height: 82)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

private struct MapGrid: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(scheme == .dark ? Color(red: 0.11, green: 0.14, blue: 0.13) : Color(red: 0.91, green: 0.94, blue: 0.91)))
            var road = Path()
            for x in stride(from: -size.height, through: size.width, by: 22) {
                road.move(to: CGPoint(x: x, y: size.height)); road.addLine(to: CGPoint(x: x + size.height * 0.7, y: 0))
            }
            for y in stride(from: 0, through: size.height + size.width, by: 28) {
                road.move(to: CGPoint(x: 0, y: y)); road.addLine(to: CGPoint(x: size.width, y: y - size.width * 0.6))
            }
            ctx.stroke(road, with: .color(.primary.opacity(0.06)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.62, y: size.height * 0.12, width: 46, height: 46)), with: .color(Color.sage.opacity(0.3)))
        }
    }
}
