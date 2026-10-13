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

    func load(context: ModelContext) async {
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
                card(.goals, "A daily goal with a streak", ((try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0) > 0),
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
            Task { await model.load(context: context) }
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
                    Text(s.title).font(.system(.title2, design: .rounded, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
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
                if card.id == .mosques || card.id == .jumuah {
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
                // One button, only when it does something.
                if s.shortcuts {
                    ShortcutsLink().shortcutsLinkStyle(.automaticOutline).frame(maxWidth: .infinity)
                } else if let action = s.action {
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

/// Each card's story: a title, one sentence, three good things, and its button (a link into shukr, Memories, or steps).
/// An item's page (decision explore-detail-layout A, owner: "pretty easily manageable and it applies to all of our different
/// pages"): one sentence, what it does as 2–4 points each with its own symbol and name (as many as it really has), how to
/// add / run / use it shown right on the page, and a button only when it does something.
struct ShowcaseStory {
    struct Point { let symbol: String; let name: String; let line: String }
    let title: String
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
    private static func control(_ name: String, _ lead: String, _ points: [Point]) -> ShowcaseStory {
        ShowcaseStory(title: name, lead: lead, points: points, how: "How to add it",
                      steps: ["Swipe down from the top-right corner, tap +, then Add a Control", "Search shukr and tap \(name)",
                              "Or on a Lock Screen button or the Action button"])
    }
    /// A Shortcuts tile (owner: Shortcuts and their cards first; Siri one point).
    private static func tile(_ name: String, _ lead: String, _ points: [Point], siri: String) -> ShowcaseStory {
        ShowcaseStory(title: name, lead: lead, points: points + [p("waveform", "Or ask Siri", siri)], how: "How to run it",
                      steps: ["Open Shortcuts and tap shukr", "Tap \(name)", "Or set it on the Action button: Settings → Action Button"],
                      action: "", shortcuts: true)
    }

    static func of(_ id: ShowcaseCardID) -> ShowcaseStory {
        switch id {
        // Home Screen
        case .homePrayers: ShowcaseStory(title: "Prayer ring", lead: "The prayer that's on and how long is left, on your Home Screen.",
            points: [p("checkmark.circle", "Mark it there", "Tap the corner circle. Scored like a tap in the app"),
                     p("circle.dashed", "A ring that grades you", "Green, then yellow, then red as time runs out"),
                     p("square.grid.2x2", "Your corners", "Qibla, Zikr, Daily Ayah or 99 Names")],
            how: "How to add it", steps: homeSteps)
        case .homeZikr: ShowcaseStory(title: "Zikr tasks", lead: "Today's zikr tasks and how far along each one is.",
            points: [p("circle.dotted.circle", "A ring for the day", "All your tasks in one glance"),
                     p("hand.tap", "Tap to start", "A task opens straight into counting")],
            how: "How to add it", steps: homeSteps)
        case .homeName: ShowcaseStory(title: "Name of the Day", lead: "One of Allah's 99 Names each day, in Arabic, with its meaning.",
            points: [p("calendar", "A new one each day", "The same Name everywhere in shukr"),
                     p("book", "Tap to read more", "Its meaning and how to learn it")],
            how: "How to add it", steps: homeSteps)
        case .homeAyah: ShowcaseStory(title: "Daily Ayah", lead: "The verse you revealed today, kept in view.",
            points: [p("eye.slash", "Never spoils it", "It shows only once you've revealed it in shukr"),
                     p("character.book.closed", "Arabic and English", "Side by side")],
            how: "How to add it", steps: homeSteps)
        case .standby: ShowcaseStory(title: "StandBy", lead: "Charging on its side, your iPhone shows the prayer ring big and dim.",
            points: [p("bed.double", "From bed", "See Fajr's time without picking it up"),
                     p("moon", "Dim red at night", "Easy on your eyes")],
            how: "How to set it up", steps: ["Add the Prayer ring to your Home Screen", "Charge your iPhone on its side, locked",
                                             "Swipe to the widgets and pick shukr"])
        // Lock Screen
        case .lockTime: ShowcaseStory(title: "Time left", lead: "In a prayer's last hour, your Lock Screen counts down the minutes.",
            points: [p("lock", "No unlocking", "Glance at it as you pick up your phone"),
                     p("hourglass", "Only when it matters", "The ring the rest of the time"),
                     p("textformat.123", "How it reads", "27m, 27:13 or 27 min, in Settings")],
            how: "How to add it", steps: lockSteps)
        case .lockCountdown: ShowcaseStory(title: "Countdown", lead: "A live countdown to the end of the prayer, and the next one's time.",
            points: [p("timer", "Counts down live", "With a bar that fills"),
                     p("arrow.right.circle", "What's next", "The next prayer underneath")],
            how: "How to add it", steps: lockSteps)
        case .lockName: ShowcaseStory(title: "Above the clock", lead: "One line above your clock: today's Name, or the prayer and when it ends.",
            points: [p("textformat", "Small and quiet", "A single line over the time")],
            how: "How to add it", steps: ["Touch and hold your Lock Screen, then tap Customize", "Tap the date above the clock", "Pick shukr's line"])
        case .lockControls: ShowcaseStory(title: "Lock Screen buttons", lead: "Swap a Lock Screen button for the qibla or your counter.",
            points: [p("location.north.line", "One press", "The qibla map, or straight into counting")],
            how: "How to add it", steps: ["Touch and hold your Lock Screen, then tap Customize", "Tap a button at the bottom, then −", "Tap + and pick a shukr control"])
        // Watch
        case .watchApp: ShowcaseStory(title: "The watch app", lead: "Your prayers and your zikr on your Apple Watch.",
            points: [p("checkmark.circle", "Mark prayers", "Hold the ring, undo if you slip"),
                     p("digitalcrown.horizontal.arrow.clockwise", "Count your way", "Tap, Double Tap or the Crown"),
                     p("location.north.line", "The qibla", "A map that taps your wrist when you face it")],
            how: "How to install it", steps: ["Open the Watch app on your iPhone", "Scroll to Available Apps", "Tap Install next to shukr"])
        case .watchFace: ShowcaseStory(title: "Your watch face", lead: "The prayer's ring as a complication, right on your watch face.",
            points: [p("circle.dashed", "Always in view", "Fills as the window passes"),
                     p("hand.tap", "Tap it", "Opens shukr on your wrist")],
            how: "How to add it", steps: ["Touch and hold your watch face, then tap Edit", "Swipe to Complications", "Tap a spot and pick shukr"])
        // Hands-free and buttons
        case .siri: ShowcaseStory(title: "Siri", lead: "Mark a prayer or ask the time left without picking up your phone.",
            points: [p("checkmark.circle", "“I prayed in shukr”", "Marks it, and tells you how you did"),
                     p("hourglass", "“How long is left in shukr”", "The time left for the prayer that's on")],
            how: "How to use it", steps: ["Say “Hey Siri”, or hold the side button", "Say the phrase, ending in “in shukr”"])
        case .answer: ShowcaseStory(title: "Notification buttons", lead: "Hold a prayer's notification to answer it.",
            points: [p("checkmark.circle", "I already prayed", "Marks it right there"),
                     p("clock.arrow.circlepath", "Nudge me later", "In 5 or 10 minutes"),
                     p("bell.badge", "Halfway and 30 minutes left", "If you haven't marked it")],
            how: "How to use it", steps: ["When a prayer's notification comes, touch and hold it", "Tap I already prayed, or a nudge"])
        case .controlCenter: ShowcaseStory(title: "Control Center", lead: "shukr a swipe away, even inside another app.",
            points: [p("clock", "The prayer that's on", "And when it ends"),
                     p("location.north.line", "The qibla", "One tap to the map")],
            how: "How to add it", steps: ["Swipe down from the top-right corner", "Tap +, then Add a Control", "Search shukr"])
        case .actionButton: ShowcaseStory(title: "Action button", lead: "Press the button on the side of your iPhone and the qibla opens.",
            points: [p("hand.point.up", "One press, any time", "No unlocking first")],
            how: "How to set it up", steps: ["Open Settings, then Action Button", "Swipe to Controls", "Choose a shukr control"])
        // Around you
        case .prayersMap: ShowcaseStory(title: "Your prayers on the map", lead: "Each prayer you mark is pinned where you prayed it, colored by how you did.",
            points: [p("line.3.horizontal.decrease.circle", "Filter", "By prayer and by dates"),
                     p("mappin", "Tap a pin", "That prayer, when and how you did")],
            action: "Open the map", link: "map")
        case .mosques: ShowcaseStory(title: "Mosques near you", lead: "The nearest first, with drive and walk times.",
            points: [p("binoculars", "Look Around", "See the entrance before you go"),
                     p("arrow.triangle.turn.up.right.diamond", "Directions", "Apple Maps or Google Maps"),
                     p("star", "Star yours", "The ones you go to, on top")],
            action: "Find mosques near me", link: "map")
        case .jumuah: ShowcaseStory(title: "Jumu'ah at the masjid", lead: "Mark Friday's Dhuhr at a masjid and it counts as Jumu'ah, full marks.",
            points: [p("building.columns", "On its own", "shukr notices the masjid you're at"),
                     p("star", "Your masjid", "Star it to give it its own pin")],
            action: "Find mosques near me", link: "map")
        // Your journey
        case .memories: ShowcaseStory(title: "Memories", lead: "After you mark a prayer, keep a photo of where you are, and you, both at once.",
            points: [p("lock", "Private", "Kept on your phone, day by day"),
                     p("magnifyingglass", "Find any", "By prayer, place, note or date"),
                     p("calendar", "On this day", "What you saw a year ago")],
            action: "Open Memories", memories: true)
        case .insights: ShowcaseStory(title: "Insights", lead: "How you're scoring, how consistent you are, and whether you're getting better.",
            points: [p("chart.bar", "Each prayer ranked", "By its recent score"),
                     p("chart.line.uptrend.xyaxis", "An 8-week trend", "Are you getting better"),
                     p("flame", "Streaks", "And a 14-day grid")],
            action: "Open Insights", link: "insights")
        // Your zikr
        case .sleep: ShowcaseStory(title: "Sleep mode", lead: "Counting in bed? Sleep mode saves your session when you drift off.",
            points: [p("moon", "Ends on its own", "45 seconds after your last tap"),
                     p("tray.and.arrow.down", "Saved at your last count", "Nothing lost"),
                     p("sun.max", "A card in the morning", "Pick up where you stopped")],
            how: "How to use it", steps: ["Start a zikr session", "Tap pause", "Turn on the moon"])
        case .tasbihFatimah: ShowcaseStory(title: "Tasbih Fatimah", lead: "33 · 33 · 34, offered each time you mark a prayer.",
            points: [p("hand.tap", "One tap", "From the Salah page"),
                     p("list.number", "Counts each phrase", "You just keep tapping")],
            action: "Go to Salah", link: "salah")
        case .goals: ShowcaseStory(title: "Daily goals", lead: "Pick a zikr and a daily goal; shukr keeps your streak.",
            points: [p("number", "A count or minutes", "Whichever suits it"),
                     p("flame", "A streak", "Every day you meet it"),
                     p("bell", "A reminder", "If you'd like one")],
            action: "Go to Zikr", link: "zikr")
        // Shortcuts (ShukrAppShortcuts.swift): each tile, its card first. The cards with buttons are iOS 26 (`available`).
        case .siriTimeLeft: tile("Time Left", "The time left for the prayer that's on, on its Live Activity card.",
            [p("checkmark.circle", "Mark it from the card", "Tap its ✓"),
             p("sunrise", "After sunrise", "The time until Dhuhr")], siri: "“How long is left in shukr”")
        case .siriPrayerTime: tile("Prayer Time", "Any prayer's time: one of the five, or the current, next or previous one.",
            [p("checkmark.seal", "Knows you prayed", "Says so first"),
             p("plus.forwardslash.minus", "For your own shortcuts", "Minutes before or after a prayer")], siri: "“When is Maghrib in shukr”")
        case .siriTodaysTimes: tile("Today’s Times", "All five of today's times in one card, the one that's on highlighted.",
            [p("circle", "Mark it", "Tap the circle beside the prayer that's on"),
             p("arrow.uturn.backward", "Unmark it", "Tap a ✓ and shukr asks first")], siri: "“Today's prayer times in shukr”")
        case .siriIPrayed: tile("I Prayed", "Marks the prayer that's on, and shows how you did on its card.",
            [p("star", "Scored at that moment", "Like a tap in the app"),
             p("arrow.uturn.backward", "Undo", "Asks in shukr, so nothing goes by mistake")], siri: "“I prayed in shukr”")
        case .siriFajrAlarm: tile("Fajr Alarm Time", "When your Fajr alarm rings next, shown as the alarm itself.",
            [p("alarm", "Even when it's off", "When it would ring"),
             p("lightbulb", "For your own shortcuts", "Lights on at that time")], siri: "“When is my Fajr alarm in shukr”")
        case .siriOpenPage: tile("Open shukr", "Straight to a page: Salah, Qibla, Zikr, Daily Ayah, the 99 Names or Memories.",
            [p("square.grid.2x2", "A tile for each page", "Pick the one you want")], siri: "“Open Qibla in shukr”")
        case .siriTasbihFatimah: tile("Open Tasbih Fatimah", "Opens straight into 33 · 33 · 34.",
            [p("list.number", "Counts each phrase", "Right after you pray")], siri: "“Start Tasbih Fatimah in shukr”")
        case .siriZikrTasks: tile("Zikr Tasks", "Today's zikr tasks in a card, with how long what's left will take.",
            [p("play.circle", "Tap a task", "shukr opens and starts counting"),
             p("arrow.clockwise", "Picks up", "From today's count")], siri: "“My zikr tasks in shukr”")
        case .siriMosques: tile("Nearby Mosques", "The nearest mosques on a map, with how far each one is.",
            [p("arrow.triangle.turn.up.right.diamond", "Directions", "Tap one and Maps opens"),
             p("map", "The full map", "Tap the map for shukr's own")], siri: "“Nearby mosques in shukr”")
        case .siriPrayedHere: tile("Prayed Here", "How many prayers you've marked where you are, and when you last prayed there.",
            [p("building.columns", "At a masjid", "Every prayer you marked there counts"),
             p("chart.bar", "Each of the five", "A count for each")], siri: "“Have I prayed here in shukr”")
        // Controls (MoreWidgets.swift): Control Center, a Lock Screen button, or the Action button. Wide or square, a control
        // shows its line of text; small, just its symbol.
        case .ccPrayer: control("Today's Prayers", "The prayer that's on and when it ends, or the next one and when it starts.",
            [p("list.bullet", "Tap it", "shukr opens on today's list"),
             p("clock", "Never out of date", "It shows a clock time, not a countdown")])
        case .ccPrayed: control("I Prayed", "Marks the prayer that's on, without opening shukr.",
            [p("star", "Scored at the tap", "Like a tap in the app"),
             p("checkmark.shield", "Never unmarks", "Already marked? It just says so")])
        case .ccFajrAlarm: control("Fajr Alarm", "Your Fajr alarm, on or off, and when it rings.",
            [p("power", "One tap", "Turns it on or off"),
             p("alarm", "When it rings", "Shown right on it")])
        case .ccQibla: control("Qibla", "Straight to the qibla map, turned so the qibla points up.",
            [p("apps.iphone", "From anywhere", "Even inside another app")])
        case .ccZikr: control("Zikr", "Straight to your zikr, and how much of it is left today.",
            [p("text.alignleft", "What's left", "Wide or square: “2 tasks left · about 9 min”"),
             p("checkmark.circle", "All done", "Says so once you've finished")])
        }
    }
}

// MARK: - The pictures (drawn like the mockup: the sage panel, the night sky, today's own prayer)

struct ShowcasePicture: View {
    let id: ShowcaseCardID
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
            } else {
                picture.scaleEffect((scale ?? (big ? 1.7 : compact ? 0.8 : 1)) * fit)
                    .id(sizeIndex)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .identity))
                    .offset(y: families.isEmpty ? 0 : 14)   // under the label row, as the setup's demo card sits under its label
            }
        }
        .overlay(alignment: .topLeading) { if !thumb && !families.isEmpty { sizeLabel } }
        .clipped()
    }

    /// Control Center's grid is wider than the other pictures: drawn at its real size, then fitted.
    private var fit: CGFloat {
        id == .controlCenter ? 0.7 : id.isControl ? 0.8 : id.isSiri ? 0.5 : !families.isEmpty ? (family == .systemSmall ? 0.68 : family == .systemMedium ? 0.55 : 0.36) : 1
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

    private var controlSymbol: String? {
        switch id {
        case .ccPrayer: prayerIcon(for: ShownPrayer.now.name)
        case .ccPrayed: "checkmark.circle"
        case .ccFajrAlarm: "alarm.fill"
        case .ccQibla: "location.north.line.fill"
        case .ccZikr: "hands.and.sparkles"
        default: nil
        }
    }

    private var sage: some View {
        LinearGradient(colors: scheme == .dark ? [Color(red: 0.17, green: 0.33, blue: 0.25), Color(red: 0.07, green: 0.10, blue: 0.08)]
                                               : [Color(red: 0.85, green: 0.92, blue: 0.87), Color(red: 0.93, green: 0.96, blue: 0.94)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// A plain cool wallpaper, so the mint Name and Ayah widgets stand out (owner: "green widget with the same kind of green
    /// background").
    private var wallpaper: some View {
        LinearGradient(colors: scheme == .dark ? [Color(red: 0.17, green: 0.19, blue: 0.23), Color(red: 0.08, green: 0.09, blue: 0.11)]
                                               : [Color(red: 0.84, green: 0.87, blue: 0.92), Color(red: 0.93, green: 0.94, blue: 0.96)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var night: some View {
        RadialGradient(colors: [Color(red: 0.23, green: 0.31, blue: 0.39), Color(red: 0.08, green: 0.10, blue: 0.11)],
                       center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 260)
    }

    @ViewBuilder private var background: some View {
        switch id {
        case .lockTime, .lockCountdown, .lockName, .lockControls, .siri, .answer, .controlCenter, .actionButton, .sleep: night
        case _ where id.isControl: night
        case _ where id.isSiri: sage   // the cards as they look in the Shortcuts app
        case .standby: Color.black
        case .prayersMap: MapGrid()
        case .homeName, .homeAyah: wallpaper
        default: sage
        }
    }

    private var fajrAlarmTime: String {
        prayerWindowToday("Fajr")?.start.formatted(date: .omitted, time: .shortened) ?? "5:37 AM"
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
        case .lockTime:
            LockClock { LockCircle(text: "\(min(p.minutesLeft, 59))m") }
        case .lockCountdown:
            LockClock {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(p.name) ends in \(min(p.minutesLeft, 59)):13").font(.system(size: 11, weight: .bold, design: .rounded))
                    Text("then the next prayer").font(.system(size: 10, design: .rounded)).opacity(0.75)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12)))
            }
        case .lockName:
            let n = NamesOfAllah.nameOfTheDay()
            LockClock(top: true) { Text("\(n.arabic) · \(n.transliteration)").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.85) }
        case .lockControls:
            HStack { LockButton(symbol: "location.north.line.fill"); Spacer(); LockButton(symbol: "circle.hexagonpath") }
                .frame(width: 150).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14)
        case .watchApp:
            WatchCase { RingFace(name: p.name, line: nil, progress: p.progress, size: 52, dark: true) }
        case .watchFace:
            WatchCase {
                VStack(spacing: 8) {
                    Text(Date(), format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute()).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    MiniArc(progress: p.progress).frame(width: 24, height: 24)
                }
            }
        case .standby:
            HStack(spacing: 14) {
                RingFace(name: p.name, line: p.left, progress: p.progress, size: 62, dark: true)
                Text(Date(), format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute()).font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(Color(red: 1, green: 0.37, blue: 0.27))
            }
        case .siri:
            VStack(spacing: 8) {
                Circle().fill(AngularGradient(colors: [.pink, .indigo, .cyan, .pink], center: .center)).frame(width: 34, height: 34)
                Text("“I prayed in shukr”").font(.system(size: 12, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
            }
        case .answer:
            VStack(alignment: .leading, spacing: 6) {
                (Text("\(p.name) 🟡 ").bold() + Text("· Halfway through \(p.name)")).font(.system(size: 11.5, design: .rounded))
                HStack(spacing: 6) {
                    Text("I prayed").frame(maxWidth: .infinity).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                    Text("10 min").frame(maxWidth: .infinity).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color(red: 0.11, green: 0.13, blue: 0.15))
            .padding(10).frame(width: 176)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.94)))
        case .controlCenter:
            // Control Center as iOS lays shukr's five controls out: a grid of 56 pt cells, medium controls two cells wide
            // (a glass capsule: the icon's round badge, then the title and value), small ones a glass circle.
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    CCPill(symbol: prayerIcon(for: p.name), title: p.name, value: p.isOn ? "ends \(shortTimePM(p.end))" : "at \(shortTimePM(p.start))").gridCellColumns(2)
                    CCCircle(symbol: "checkmark.circle")
                    CCCircle(symbol: "location.north.line.fill")
                }
                GridRow {
                    CCPill(symbol: "alarm.fill", title: "Fajr Alarm", value: fajrAlarmTime, on: true).gridCellColumns(2)
                    CCCircle(symbol: "hands.and.sparkles")
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
                Text(MosqueFavorites.all.first?.name ?? "Your masjid").font(.system(size: 13, weight: .semibold, design: .rounded))
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
                PrayerCardSnippet(state: .init(label: p.name, start: p.start, end: p.end, symbol: prayerIcon(for: p.name), dark: scheme == .dark))
            }
        case .siriPrayerTime:
            ShortcutSheetShot(dialog: "\(p.name) is \(p.isOn ? "on until \(shortTimePM(p.end))" : "at \(shortTimePM(p.start))").") {
                NextPrayerSnippet(name: p.name, start: p.start)
            }
        case .siriTodaysTimes:
            ShortcutSheetShot(dialog: TodaysTimesSnippet.spoken()) { TodaysTimesSnippet(rows: TodaysTimesSnippet.rows(), markable: true) }
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
        case .ccPrayer:
            CCPill(symbol: prayerIcon(for: p.name), title: p.name, value: p.isOn ? "ends \(shortTimePM(p.end))" : "at \(shortTimePM(p.start))")
        case .ccPrayed:
            HStack(spacing: 12) {
                CCPill(symbol: "checkmark.circle", title: p.name, value: "Mark prayed")
                CCCircle(symbol: "checkmark.circle")
            }
        case .ccFajrAlarm:
            HStack(spacing: 12) {
                CCPill(symbol: "alarm.fill", title: "Fajr Alarm", value: fajrAlarmTime, on: true)
                CCCircle(symbol: "alarm.fill", on: true)
            }
        case .ccQibla:
            HStack(spacing: 12) { CCPill(symbol: "location.north.line.fill", title: "Qibla", value: nil); CCCircle(symbol: "location.north.line.fill") }
        case .ccZikr:
            HStack(spacing: 12) { CCPill(symbol: "hands.and.sparkles", title: "Zikr", value: "2 tasks left · about 9 min"); CCCircle(symbol: "hands.and.sparkles") }
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
private struct CCPill: View {
    let symbol: String
    let title: String
    let value: String?
    var on = false
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
private struct CCCircle: View {
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
/// The Prayers widget itself, at a small widget's size, from the widget's own data (`makeEntry`). `playing` (an item's page)
/// runs what a person does with it, a finger mark on each tap: the ring's tap flips to time left, the arrow opens today's
/// list, and back. It never takes a touch: its buttons would really run.
struct RealPrayersWidget: View {
    var playing = false
    @State private var entry: PrayersWidgetEntry?
    @State private var touch: UnitPoint?
    @State private var touches = 0
    @Environment(\.colorScheme) private var scheme
    static let side: CGFloat = 170

    var body: some View {
        ZStack {
            if let entry { PrayersWidgetView(entry: entry).padding(14) }
        }
        .frame(width: Self.side, height: Self.side)
        .background(entry?.background ?? WidgetSoft.surface(scheme))
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
        }
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .allowsHitTesting(false)
        .task { await run() }
    }

    private func run() async {
        let first = await PrayersWidgetTimelineProvider().makeEntry()
        entry = first
        guard playing else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2.2))
            await tap(at: .center) { $0.with(text: !$0.textToggle) }       // the ring: ends at ⇄ time left
            try? await Task.sleep(for: .seconds(2.2))
            await tap(at: UnitPoint(x: 0.5, y: 0.9)) { $0.at($0.date, list: true) }   // the arrow: today's list
            try? await Task.sleep(for: .seconds(3))
            await tap(at: UnitPoint(x: 0.5, y: 0.9)) { $0.at($0.date, list: false).with(text: first.textToggle) }
        }
    }

    @MainActor private func tap(at point: UnitPoint, _ change: (PrayersWidgetEntry) -> PrayersWidgetEntry) async {
        guard let current = entry, !Task.isCancelled else { return }
        touches += 1
        withAnimation(.easeOut(duration: 0.15)) { touch = point }
        try? await Task.sleep(for: .seconds(0.18))
        withAnimation(.easeInOut(duration: 0.35)) { entry = change(current) }
        withAnimation(.easeOut(duration: 0.3)) { touch = nil }
    }
}

extension PrayersWidgetEntry {
    /// The same entry with the ring's text side flipped (the widget's own tap).
    func with(text: Bool) -> PrayersWidgetEntry {
        PrayersWidgetEntry(date: date, heading: heading, latitude: latitude, longitude: longitude,
                           toggleShowAllTImes: toggleShowAllTImes, prayerDict: prayerDict,
                           todayPrayerTimes: todayPrayerTimes, locationName: locationName, textToggle: text,
                           completedScores: completedScores, nextFajr: nextFajr, nextSunrise: nextSunrise,
                           leftCorner: leftCorner, rightCorner: rightCorner, scoreColors: scoreColors,
                           ringAbove: ringAbove, style: style)
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

/// The Zikr widget itself at one size: your tasks, or stand-ins without any.
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

/// The Daily Ayah widget itself at one size: today's verse once it's revealed, else the widget's own sample (never spoils
/// the reveal).
struct RealAyahWidget: View {
    var family: WidgetFamily = .systemMedium
    var body: some View {
        SizedWidget(family: family) {
            DailyAyahWidgetView(entry: DailyAyahEntry(date: Date(),
                                                      ayah: DailyAyahWidgetPayload.load().flatMap { $0.isToday ? $0 : nil } ?? DailyAyahProvider.sample),
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

/// Stand-ins for cards that need data the phone may not have yet.
@MainActor enum ShowcaseSamples {
    static var zikrTasks: [ZikrTaskSnapshot] {
        if let today = ZikrTaskSnapshot.today(), !today.isEmpty { return today }
        return [ZikrTaskSnapshot(id: "1", name: "Subhanallah", isCountMode: true, goal: 100, count: 40, minutes: 0, done: false, secondsLeft: 120),
                ZikrTaskSnapshot(id: "2", name: "Astaghfirullah", isCountMode: true, goal: 100, count: 0, minutes: 0, done: false, secondsLeft: 200),
                ZikrTaskSnapshot(id: "3", name: "Alhamdulillah", isCountMode: true, goal: 33, count: 33, minutes: 0, done: true)]
    }
    static var mosques: NearbyMosquesSearch.Outcome {
        let here = CLLocation(latitude: 0, longitude: 0)
        let names = MosqueFavorites.all.prefix(1).map(\.name) + ["Masjid Al-Noor", "Islamic Center", "Masjid Ar-Rahman"]
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
        s.place = MosqueFavorites.all.first?.name ?? "Your masjid"
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
            Text(Date(), format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            if !top { accessory() }
        }
        .foregroundStyle(.white)
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
