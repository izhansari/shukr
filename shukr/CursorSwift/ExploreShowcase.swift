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
    /// In a group's pager (ExploreStoryPager): the next member, the group's name for the last page's way back, and the tap.
    var next: ShowcaseCard? = nil
    var backTitle: String? = nil
    var onNext: (() -> Void)? = nil
    /// The pager marks a page opened when it's the one shown (its neighbours are built early).
    var marksOpened = true
    /// The page's side margin: the pager sets its own (the neighbours peek in at the edges).
    var sideInset: CGFloat = 16
    @State private var showSteps = false
    @AppStorage(MasjidArrival.enabledKey) private var arrivalDuas = false

    var body: some View {
        let s = ShowcaseStory.of(card.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ShowcasePicture(id: card.id, big: true)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.title).font(.system(.title2, design: .rounded, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(s.lead).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 0) {
                    ForEach(Array(s.points.enumerated()), id: \.offset) { i, point in
                        if i > 0 { Divider().padding(.leading, 44) }
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark").font(.system(.subheadline, weight: .heavy)).foregroundStyle(Color.sage)
                                .frame(width: 20)
                            Text(point).font(.system(.subheadline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
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
                if let steps = s.steps, showSteps {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.system(.footnote, design: .rounded, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 24, height: 24).background(Circle().fill(Color.sage))
                                Text(step).font(.system(.subheadline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Button {
                    triggerSomeVibration(type: .light)
                    if let link = s.link { NotificationCenter.default.post(name: WhatsNew.go, object: link) }
                    else if s.memories { MemoriesPresenter.shared.open = true }
                    else { withAnimation(.snappy(duration: 0.3)) { showSteps.toggle() } }
                } label: {
                    Text(s.steps != nil && showSteps ? "Got it" : s.button)
                        .font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Color.sage))
                }
                .buttonStyle(.plain)
                if s.steps != nil, !showSteps {
                    Text("\(s.steps?.count ?? 0) quick steps").font(.system(.subheadline, design: .rounded)).foregroundStyle(Color.sage)
                        .frame(maxWidth: .infinity)
                }
                if card.id == .siri || card.id.isSiri {
                    ShortcutsLink().shortcutsLinkStyle(.automaticOutline).frame(maxWidth: .infinity)
                }
                if let onNext { nextCard(onNext) }
            }
            .padding(.vertical, 16).padding(.horizontal, sideInset)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .onAppear { if marksOpened { UserDefaults.standard.set(true, forKey: ExploreShowcase.openedKey(card.id)) } }
    }

    /// "Next · I Prayed ›" at the foot (owner, decision explore-story-next D — swiping works too); the last page's goes back.
    private func nextCard(_ go: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            go()
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let next {
                        ShowcasePicture(id: next.id, thumb: true)
                            .frame(width: 124, height: 124).scaleEffect(0.42).frame(width: 52, height: 52)
                    } else {
                        Image(systemName: "square.grid.2x2").font(.system(size: 20)).foregroundStyle(Color.sage)
                            .frame(width: 52, height: 52).background(Color.sage.opacity(0.12))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(next == nil ? "That's all" : "Next").font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                    Text(next?.id.memberName ?? "Back to \(backTitle ?? "the list")")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                Spacer(minLength: 8)
                Image(systemName: next == nil ? "chevron.left" : "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

/// Each card's story: a title, one sentence, three good things, and its button (a link into shukr, Memories, or steps).
struct ShowcaseStory {
    let title: String
    let lead: String
    let points: [String]
    var button = "Show me how"
    var steps: [String]? = nil
    var link: String? = nil
    var memories = false

    static let homeSteps = ["Touch and hold an empty spot on your Home Screen", "Tap Edit, then Add Widget", "Search shukr and pick the one you want"]
    static let lockSteps = ["Touch and hold your Lock Screen, then tap Customize", "Pick your Lock Screen, then tap under the clock",
                            "Find shukr and tap the ones you want"]

    /// A Shortcuts tile (owner 2026-10-13: Shortcuts and their cards first — "our name isn't easy to say", Siri is an aside).
    private static func tileStory(_ tile: String, _ lead: String, _ points: [String], siri: String) -> ShowcaseStory {
        ShowcaseStory(title: tile, lead: lead, points: points + ["Or ask Siri: \(siri)"], button: "Show me how",
                      steps: ["Open the Shortcuts app and tap shukr", "Tap \(tile)", "Or put it on the Action button: Settings → Action Button → Shortcut"])
    }
    private static func controlStory(_ name: String, _ lead: String, _ points: [String]) -> ShowcaseStory {
        ShowcaseStory(title: name, lead: lead, points: points + [], button: "Add it",
                      steps: ["Swipe down from the top-right corner, then tap + and Add a Control", "Search shukr and pick \(name)",
                              "On your Lock Screen or Action button instead: Customize the Lock Screen, or Settings → Action Button"])
    }

    static func of(_ id: ShowcaseCardID) -> ShowcaseStory {
        switch id {
        case .homePrayers: ShowcaseStory(title: "Your prayer ring, on your Home Screen",
            lead: "The prayer that's on, how long is left, and a tap to mark it, without opening shukr.",
            points: ["The ring turns from green to red as time runs out", "Tap the corner circle to mark it, scored like in the app",
                     "Choose its corners: Qibla, Tasbeeh, Daily Ayah or 99 Names"], button: "Add the widget", steps: homeSteps)
        case .homeZikr: ShowcaseStory(title: "Today's zikr, at a glance",
            lead: "Your tasks for today and how many are left, like the Reminders widget.",
            points: ["A ring for the whole day", "Each task fills as you go", "Tap a task to start it"], button: "Add the widget", steps: homeSteps)
        case .homeName: ShowcaseStory(title: "A Name of Allah each day",
            lead: "One of the 99 Names on your Home Screen every day, in Arabic, with its meaning.",
            points: ["The same Name everywhere, every day", "Tap it to read more", "Learn all 99 without trying"], button: "Add the widget", steps: homeSteps)
        case .homeAyah: ShowcaseStory(title: "Today's verse, on your Home Screen",
            lead: "The verse you revealed today, kept in view.",
            points: ["It never spoils the reveal", "Arabic and English", "A new one every day"], button: "Add the widget", steps: homeSteps)
        case .lockTime: ShowcaseStory(title: "Time left, on your Lock Screen",
            lead: "In a prayer's last hour, your Lock Screen counts down the minutes. No unlocking, no opening shukr.",
            points: ["Only in the last hour, so it speaks up when it matters", "Your own times, wherever you are",
                     "Pick how it reads: 27m, 27:13 or 27 min"], button: "Add to Lock Screen", steps: lockSteps)
        case .lockCountdown: ShowcaseStory(title: "A countdown, and what's next",
            lead: "A live countdown to the end of the prayer, and the next one's time.",
            points: ["A bar that fills as time passes", "The next prayer underneath", "Glance at it, no unlocking"],
            button: "Add to Lock Screen", steps: lockSteps)
        case .lockName: ShowcaseStory(title: "The Name of the Day, above the time",
            lead: "One line above your clock: today's Name of Allah.",
            points: ["Small and quiet", "A new Name each day", "Or the prayer and when it ends, if you'd rather"],
            button: "Add to Lock Screen", steps: ["Touch and hold your Lock Screen, then tap Customize", "Tap the date above the clock",
                                                  "Pick shukr's line"])
        case .lockControls: ShowcaseStory(title: "Qibla and tasbeeh, on your Lock Screen",
            lead: "Swap a Lock Screen button for the qibla or your counter.",
            points: ["One press from the Lock Screen", "The qibla map, or straight into counting", "Works in the dark, with gloves on"],
            button: "Show me how", steps: ["Touch and hold your Lock Screen, then tap Customize", "Tap a button at the bottom, then −",
                                           "Tap + and pick a shukr control"])
        case .watchApp: ShowcaseStory(title: "shukr on your wrist",
            lead: "Your prayers and your zikr on your Apple Watch.",
            points: ["Hold the ring to mark a prayer, undo if you slip", "Count with a tap, Double Tap or the Crown",
                     "A qibla map that taps your wrist when you face it"], button: "Install on your watch",
            steps: ["Open the Watch app on your iPhone", "Scroll to Available Apps", "Tap Install next to shukr"])
        case .watchFace: ShowcaseStory(title: "The ring on your watch face",
            lead: "The prayer's ring as a complication, right on your watch face.",
            points: ["Always in view on your wrist", "Fills as the window passes", "Tap it to open shukr"], button: "Show me how",
            steps: ["Touch and hold your watch face, then tap Edit", "Swipe to Complications", "Tap a spot and pick shukr"])
        case .standby: ShowcaseStory(title: "Your ring on the nightstand",
            lead: "Charging on its side, your iPhone shows the prayer ring big and dim.",
            points: ["See Fajr's time from bed", "Dim red at night", "Uses the Home Screen widget"], button: "Show me how",
            steps: ["Add the Prayers widget to your Home Screen", "Charge your iPhone on its side, locked", "Swipe to the widgets and pick shukr"])
        case .siri: ShowcaseStory(title: "Ask Siri to mark a prayer",
            lead: "Mark a prayer or ask the time left, without picking up your phone. Say “in shukr” at the end.",
            points: ["“I prayed in shukr” marks it", "“How long is left in shukr”", "“Start Tasbih Fatimah in shukr”"], button: "Try a phrase",
            steps: ["Say “Hey Siri”, or hold the side button", "Say “How long is left in shukr”", "Siri answers with the time left"])
        case .answer: ShowcaseStory(title: "Answer right from the notification",
            lead: "Hold a prayer's notification to answer it.",
            points: ["“I already prayed” marks it", "“Nudge in 5 minutes”, or 10", "Halfway and 30 minutes left, if you haven't marked it"],
            button: "Show me how", steps: ["When a prayer's notification comes, touch and hold it", "Tap I already prayed, or a nudge", "Done, without opening shukr"])
        case .controlCenter: ShowcaseStory(title: "Qibla in Control Center",
            lead: "shukr a swipe away, even inside another app.",
            points: ["The prayer that's on and its time", "Straight to the qibla map", "Or straight into your zikr"], button: "Show me how",
            steps: ["Swipe down from the top-right corner", "Tap + at the top left, then Add a Control", "Search shukr and add the ones you want"])
        case .actionButton: ShowcaseStory(title: "Qibla on your Action button",
            lead: "Press the button on the side of your iPhone and the qibla opens.",
            points: ["One press, any time", "No unlocking first", "Or make it start your counter"], button: "Show me how",
            steps: ["Open Settings, then Action Button", "Swipe to Controls", "Choose a shukr control"])
        case .prayersMap: ShowcaseStory(title: "Every prayer, where you prayed it",
            lead: "Each prayer you mark is pinned where you prayed it, coloured by how you did.",
            points: ["Filter by prayer and dates", "Tap a pin for that prayer", "The qibla line from where you stand"],
            button: "Open the map", link: "map")
        case .jumuah: ShowcaseStory(title: "Jumu'ah, counted at the masjid",
            lead: "Mark Friday's Dhuhr at a masjid and it counts as Jumu'ah, full marks.",
            points: ["shukr notices the masjid on its own", "Star yours to give it its own pin", "A dua when you arrive, if you'd like"],
            button: "Find mosques near me", link: "map")
        case .mosques: ShowcaseStory(title: "Mosques near you",
            lead: "The nearest first, with drive and walk times.",
            points: ["Look Around to see the entrance", "Directions in Apple Maps or Google Maps", "Star the ones you go to"],
            button: "Find mosques near me", link: "map")
        case .memories: ShowcaseStory(title: "A photo with each prayer",
            lead: "After you mark a prayer, keep a photo of where you are, and you, both at once.",
            points: ["Kept day by day, private to your phone", "Find any by prayer, place, note or date", "On this day, a year ago"],
            button: "Open Memories", memories: true)
        case .insights: ShowcaseStory(title: "See which prayer needs you most",
            lead: "How you're scoring, how consistent you are, and whether you're getting better.",
            points: ["Each prayer ranked by its recent score", "An 8-week trend", "Streaks and a 14-day grid"],
            button: "Open Insights", link: "insights")
        case .sleep: ShowcaseStory(title: "Count until you fall asleep",
            lead: "Counting in bed? Sleep mode saves your session when you drift off.",
            points: ["Ends 45 seconds after your last tap", "Saved at your last count", "A gentle card in the morning"],
            button: "Show me how", steps: ["Start a zikr session", "Tap pause", "Turn on the moon chip"])
        case .tasbihFatimah: ShowcaseStory(title: "Tasbih Fatimah, after every prayer",
            lead: "33 · 33 · 34, offered each time you mark a prayer.",
            points: ["One tap from the Salah page", "Counts each phrase for you", "✕ when you'd rather not"], button: "Go to Salah", link: "salah")
        // Shortcuts: each tile as built (ShukrAppShortcuts.swift; Sami, 2026-10-13), its card first; Siri one line. The cards
        // with buttons are iOS 26 (`available` hides them before).
        case .siriTimeLeft: tileStory("Time Left", "The time left for the prayer that's on, on its Live Activity card.",
            ["Tap the card's ✓ to mark the prayer", "Between Sunrise and Dhuhr, the time until Dhuhr"], siri: "“How long is left in shukr”")
        case .siriPrayerTime: tileStory("Prayer Time", "Any prayer's time: one of the five, or the current, next or previous one.",
            ["Prayed it already? It says so first", "In your own shortcuts: minutes before or after a prayer"], siri: "“When is Maghrib in shukr”")
        case .siriTodaysTimes: tileStory("Today’s Times", "All five of today's times in one card, the one that's on highlighted with its time left.",
            ["Tap the circle to mark the prayer that's on", "Tap a ✓ and shukr asks to unmark it"], siri: "“Today's prayer times in shukr”")
        case .siriIPrayed: tileStory("I Prayed", "Marks the prayer that's on, and shows how you did on its card.",
            ["Scored at that moment, like a tap in the app", "Undo asks in shukr, so nothing goes by mistake"], siri: "“I prayed in shukr”")
        case .siriFajrAlarm: tileStory("Fajr Alarm Time", "When your Fajr alarm rings next, shown as the alarm itself.",
            ["Says so if it's off, and when it would ring", "In your own shortcuts: lights on at that time"], siri: "“When is my Fajr alarm in shukr”")
        case .siriOpenPage: tileStory("Open shukr", "Straight to a page: Salah, Qibla, Zikr, Daily Ayah, the 99 Names or Memories.",
            ["A tile for each page", "Handy on the Action button"], siri: "“Open Qibla in shukr”")
        case .siriTasbihFatimah: tileStory("Open Tasbih Fatimah", "Opens straight into 33 · 33 · 34.",
            ["Right after you pray", "Counts each phrase for you"], siri: "“Start Tasbih Fatimah in shukr”")
        case .siriZikrTasks: tileStory("Zikr Tasks", "Today's zikr tasks in a card, with how long what's left will take.",
            ["Tap a task: shukr opens and starts counting", "Picks up from today's count"], siri: "“My zikr tasks in shukr”")
        case .siriMosques: tileStory("Nearby Mosques", "The nearest mosques on a map, with how far each one is.",
            ["Tap one for directions in Maps", "Tap the map for shukr's own"], siri: "“Nearby mosques in shukr”")
        case .siriPrayedHere: tileStory("Prayed Here", "How many prayers you've marked where you are, and when you last prayed there.",
            ["At a masjid, every prayer you marked there counts", "A count for each of the five"], siri: "“Have I prayed here in shukr”")
        // Controls (MoreWidgets.swift) as built: Control Center, a Lock Screen button, or the Action button. Wide or square,
        // a control shows its line of text; small, just its symbol.
        case .ccPrayer: controlStory("Today's Prayers", "The prayer that's on and when it ends, or the next one and when it starts.",
            ["Tap it: shukr opens on today's list", "A clock time, so it's never out of date", "Wide or square to see the time"])
        case .ccPrayed: controlStory("I Prayed", "Marks the prayer that's on, without opening shukr.",
            ["Scored at the tap", "Already marked? It says so, and never unmarks", "Made for the Action button"])
        case .ccFajrAlarm: controlStory("Fajr Alarm", "Your Fajr alarm, on or off, and when it rings.",
            ["One tap turns it on or off", "Shows when it rings next", "The same alarm as in Settings"])
        case .ccQibla: controlStory("Qibla", "Straight to the qibla map, turned so the qibla points up.",
            ["From anywhere, even inside another app", "One press on the Lock Screen", "Or on the Action button"])
        case .ccZikr: controlStory("Zikr", "Straight to your zikr, and how much of it is left today.",
            ["Wide or square: “2 tasks left · about 9 min”", "“All done today” once you've finished", "One tap into counting"])
        case .goals: ShowcaseStory(title: "A daily goal, with a streak",
            lead: "Pick a zikr and a daily goal; shukr keeps your streak.",
            points: ["A count or minutes", "Every day you meet it, the streak grows", "A reminder, if you'd like"], button: "Go to Zikr", link: "zikr")
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The picture sits over the panel and never sizes it (a wide one — a row of tiles — pushed the whole page past
        // the screen's edges).
        background.overlay {
            if thumb, let symbol = controlSymbol {
                CCCircle(symbol: symbol, on: id == .ccFajrAlarm).scaleEffect(1.5)
            } else {
                picture.scaleEffect((scale ?? (big ? 1.7 : compact ? 0.8 : 1)) * fit)
            }
        }
        .clipped()
    }

    /// Control Center's grid is wider than the other pictures: drawn at its real size, then fitted.
    private var fit: CGFloat { id == .controlCenter ? 0.7 : id.isControl ? 0.8 : id.isSiri ? 0.5 : 1 }

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
        case .homeName: LinearGradient(colors: [Color(red: 0.18, green: 0.42, blue: 0.33), Color(red: 0.56, green: 0.77, blue: 0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
        case .prayersMap: MapGrid()
        default: sage
        }
    }

    private var fajrAlarmTime: String {
        prayerWindowToday("Fajr")?.start.formatted(date: .omitted, time: .shortened) ?? "5:37 AM"
    }

    @ViewBuilder private var picture: some View {
        let p = ShownPrayer.now
        switch id {
        case .homePrayers:
            WidgetTile { RingFace(name: p.name, line: p.left, progress: p.progress, size: 62) }
        case .homeZikr:
            WidgetTile {
                VStack(alignment: .leading, spacing: 6) {
                    ZikrRow(name: "Astaghfirullah", fill: 1); ZikrRow(name: "Salawat", fill: 0.6); ZikrRow(name: "SubhanAllah", fill: 0.2)
                }
            }
        case .homeName:
            let n = NamesOfAllah.nameOfTheDay()
            WidgetTile(fill: Color(red: 0.98, green: 0.97, blue: 0.94)) {
                VStack(spacing: 3) {
                    Text(n.arabic).font(.system(size: 20)).foregroundStyle(Color(red: 0.18, green: 0.35, blue: 0.27))
                    Text(n.meaning).font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                }
                .padding(.horizontal, 4)
            }
        case .homeAyah:
            WidgetTile(width: 170, height: 82) {
                VStack(spacing: 4) {
                    Text("رَبِّ زِدْنِي عِلْمًا").font(.system(size: 16)).foregroundStyle(Color(red: 0.18, green: 0.35, blue: 0.27))
                    Text("Ta-Ha · 20:114").font(.system(size: 9.5, design: .rounded)).foregroundStyle(.secondary)
                }
            }
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
