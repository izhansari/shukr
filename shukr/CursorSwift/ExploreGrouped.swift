//
//  ExploreGrouped.swift
//  shukr
//
//  Settings → Explore shukr, grouped (owner, 2026-10-13: "it's kinda intense … 1 new but … not clear what i need to
//  satisfy … 16 of 20 … not sure which … put like items together … all the home screen widgets. then all the lock screen
//  widgets. all the shortcuts. all the control center ones" → "yeah"). About ten group cards in two sections, Beyond the
//  app and Inside shukr, each saying where you stand ("2 of 4 added" · Try it · ✓); no overall ring. Something new sits
//  first under "New" and opening it clears it (the Settings row's "1 new"). A group opens its members, each with ✓ or how
//  to add it (the showcase's story page). The default; the others are in My Dev Stuff → Explore page.
//

import SwiftUI
import SwiftData

enum ExploreGroupID: String, CaseIterable, Identifiable {
    case homeWidgets, lockWidgets, controls, siri, watch, answer, mapMasjid, memories, insights, zikrExtras
    var id: String { rawValue }

    var title: String {
        switch self {
        case .homeWidgets: "Home Screen widgets"
        case .lockWidgets: "Lock Screen widgets"
        case .controls: "Control Center and buttons"
        case .siri: "Shortcuts"
        case .watch: "Apple Watch"
        case .answer: "Answer from notifications"
        case .mapMasjid: "The map and your masjid"
        case .memories: "Memories"
        case .insights: "Insights"
        case .zikrExtras: "Zikr extras"
        }
    }
    /// What's inside, a few words (the card).
    var line: String {
        switch self {
        case .homeWidgets: "Prayer ring, zikr, the Name, the verse, StandBy"
        case .lockWidgets: "Time left, a countdown, the Name above the clock"
        case .controls: "Today's Prayers, I Prayed, Fajr Alarm, Qibla, Zikr"
        case .siri: "Cards for time left, today's times and mosques near you"
        case .watch: "The app and your watch face"
        case .answer: "I already prayed · nudge me later"
        case .mapMasjid: "Your prayers on the map, mosques, Jumu'ah"
        case .memories: "A photo with each prayer"
        case .insights: "Which prayer needs you most"
        case .zikrExtras: "Sleep mode, Tasbih Fatimah, daily goals"
        }
    }
    /// What you get, one sentence (the group's page).
    var lead: String {
        switch self {
        case .homeWidgets: "Your prayer, your zikr, the Name of the Day and today's verse on your Home Screen, and on your nightstand while it charges."
        case .lockWidgets: "Time left and what's next, every time you pick up your phone, without unlocking it."
        case .controls: "Five controls for Control Center, your Lock Screen buttons or the Action button. Make one wide or square and it shows a line of text too."
        case .siri: "Tap a tile in the Shortcuts app and shukr answers with a card you can tap. Run them from the Action button too, or by asking Siri."
        case .watch: "Your prayers and your zikr on your wrist, and the ring on your watch face."
        case .answer: "Mark a prayer, or ask for a nudge, right from its notification."
        case .mapMasjid: "Every prayer pinned where you prayed it, mosques near you, and Jumu'ah counted at the masjid."
        case .memories: "A photo after you pray, kept day by day."
        case .insights: "How you're scoring, how consistent you are, and which prayer needs you most."
        case .zikrExtras: "Small things that make counting easier."
        }
    }
    var members: [ShowcaseCardID] {
        switch self {
        case .homeWidgets: [.homePrayers, .homeZikr, .homeName, .homeAyah, .standby]
        case .lockWidgets: [.lockTime, .lockCountdown, .lockName]
        case .controls: [.ccPrayer, .ccPrayed, .ccFajrAlarm, .ccQibla, .ccZikr]
        case .siri: [.siriTimeLeft, .siriPrayerTime, .siriTodaysTimes, .siriIPrayed, .siriFajrAlarm, .siriOpenPage, .siriTasbihFatimah,
                     .siriZikrTasks, .siriMosques, .siriPrayedHere]
        case .watch: [.watchApp, .watchFace]
        case .answer: [.answer]
        case .mapMasjid: [.prayersMap, .mosques, .jumuah]
        case .memories: [.memories]
        case .insights: [.insights]
        case .zikrExtras: [.sleep, .tasbihFatimah, .goals]
        }
    }
    /// The card whose picture stands for the group.
    var picture: ShowcaseCardID {
        switch self {
        case .homeWidgets: .homePrayers
        case .lockWidgets: .lockTime
        case .controls: .controlCenter
        case .siri: .siriTodaysTimes
        case .watch: .watchApp
        case .answer: .answer
        case .mapMasjid: .prayersMap
        case .memories: .memories
        case .insights: .insights
        case .zikrExtras: .sleep
        }
    }
    var insideShukr: Bool { [.mapMasjid, .memories, .insights, .zikrExtras].contains(self) }
    /// The word for a member that's done ("2 of 4 added").
    var doneWord: String {
        switch self {
        case .homeWidgets, .lockWidgets, .controls: "added"
        case .siri: "tried"
        default: "tried"
        }
    }
}

/// A member's short name in its group's list.
extension ShowcaseCardID {
    /// What it does, one line under its name in the group's list.
    var memberLine: String {
        switch self {
        case .homePrayers: "The prayer that's on, marked with a tap"
        case .homeZikr: "Today's tasks and what's left"
        case .homeName: "One of the 99 Names each day"
        case .homeAyah: "The verse you revealed today"
        case .standby: "Your ring, big and dim, while it charges"
        case .lockTime: "Minutes left in a prayer's last hour"
        case .lockCountdown: "A live countdown, and the next prayer"
        case .lockName: "Today's Name, above the clock"
        case .lockControls: "The qibla or your counter, one press away"
        case .controlCenter: "shukr a swipe away"
        case .actionButton: "The qibla on the side button"
        case .watchApp: "Mark prayers and count zikr on your wrist"
        case .watchFace: "The prayer's ring as a complication"
        case .siri: "Ask Siri to mark a prayer"
        case .answer: "Mark it or snooze it from the notification"
        case .prayersMap: "Every prayer pinned where you prayed it"
        case .mosques: "The nearest first, with directions"
        case .jumuah: "Friday at a masjid counts as Jumu'ah"
        case .memories: "A photo after each prayer"
        case .insights: "Which prayer needs you most"
        case .sleep: "Saves your count if you drift off"
        case .tasbihFatimah: "33 · 33 · 34, offered after each prayer"
        case .goals: "A daily goal, and a streak for keeping it"
        case .siriTimeLeft: "A card with the time left to pray"
        case .siriPrayerTime: "Any prayer's time, for your own shortcuts"
        case .siriTodaysTimes: "A card with all five of today's times"
        case .siriIPrayed: "Marks the prayer that's on, with a card"
        case .siriFajrAlarm: "When your Fajr alarm rings next"
        case .siriOpenPage: "Opens a page: Qibla, Zikr, Memories…"
        case .siriTasbihFatimah: "Starts 33 · 33 · 34"
        case .siriZikrTasks: "Your tasks in a card. Tap one to start it"
        case .siriMosques: "The nearest mosques, on a map"
        case .siriPrayedHere: "How often you've prayed where you are"
        case .ccPrayer: "Shows the prayer that's on. Opens today's list"
        case .ccPrayed: "Marks the prayer that's on, in one tap"
        case .ccFajrAlarm: "Turns your Fajr alarm on or off"
        case .ccQibla: "Opens the qibla map"
        case .ccZikr: "Opens your zikr, and shows what's left"
        }
    }

    /// The Siri cards with buttons are iOS 26 only (decision shortcut-buttons-ios26 A): before 26 they aren't offered.
    var available: Bool {
        if #available(iOS 26.0, *) { return true }
        return ![.siriTimeLeft, .siriTodaysTimes, .siriIPrayed, .siriZikrTasks, .siriMosques, .siriPrayedHere].contains(self)
    }

    var memberName: String {
        switch self {
        case .homePrayers: "Prayer ring"
        case .homeZikr: "Zikr tasks"
        case .homeName: "Name of the Day"
        case .homeAyah: "Daily Ayah"
        case .standby: "StandBy, on your nightstand"
        case .lockTime: "Time left"
        case .lockCountdown: "Countdown and what's next"
        case .lockName: "The Name above the clock"
        case .lockControls: "Lock Screen buttons"
        case .controlCenter: "Control Center"
        case .actionButton: "Action button"
        case .watchApp: "The watch app"
        case .watchFace: "Your watch face"
        case .siri: "Siri"
        case .answer: "Notification buttons"
        case .prayersMap: "Your prayers on the map"
        case .mosques: "Mosques near you"
        case .jumuah: "Jumu'ah at the masjid"
        case .memories: "Memories"
        case .insights: "Insights"
        case .sleep: "Sleep mode"
        case .tasbihFatimah: "Tasbih Fatimah after prayer"
        case .goals: "Daily goals with streaks"
        // The Shortcuts tiles' own names (ShukrAppShortcuts.swift).
        case .siriTimeLeft: "Time Left"
        case .siriPrayerTime: "Prayer Time"
        case .siriTodaysTimes: "Today’s Times"
        case .siriIPrayed: "I Prayed"
        case .siriFajrAlarm: "Fajr Alarm Time"
        case .siriOpenPage: "Open shukr"
        case .siriTasbihFatimah: "Open Tasbih Fatimah"
        case .siriZikrTasks: "Zikr Tasks"
        case .siriMosques: "Nearby Mosques"
        case .siriPrayedHere: "Prayed Here"
        case .ccPrayer: "Today's Prayers"
        case .ccPrayed: "I Prayed"
        case .ccFajrAlarm: "Fajr Alarm"
        case .ccQibla: "Qibla"
        case .ccZikr: "Zikr"
        }
    }
}

struct ExploreGroup: Identifiable, Hashable {
    static func == (a: ExploreGroup, b: ExploreGroup) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    let id: ExploreGroupID
    let members: [ShowcaseCard]
    var found: Int { members.filter(\.using).count }
    var complete: Bool { found == members.count }
    var isNew: Bool { members.contains(where: \.isNew) }
    /// Where you stand: "2 of 4 added" · Try it · ✓ (one member: ✓ Using).
    var status: String {
        if complete { return members.count > 1 ? "✓ All \(id.doneWord)" : "✓ Using" }
        if found > 0 { return "\(found) of \(members.count) \(id.doneWord)" }
        return "Try it"
    }
}

enum ExploreGrouped {
    /// The Settings row's count: groups with something new not yet opened.
    static var newCount: Int {
        ExploreGroupID.allCases.filter { g in g.members.filter(\.available).contains { ExploreShowcase.isNew($0) } }.count
    }
}

// MARK: - The page

struct ExploreGroupedPage: View {
    @State private var model = ShowcaseModel()
    @Environment(\.modelContext) private var context
    /// DEBUG `-demoExploreGroup siri`: that group's page, pushed once loaded (screenshots).
    @State private var demoGroup: ExploreGroup?

    private var groups: [ExploreGroup] {
        let cards = model.byID
        return ExploreGroupID.allCases.compactMap { g in
            let members = g.members.filter(\.available).compactMap { cards[$0] }
            return members.isEmpty ? nil : ExploreGroup(id: g, members: members)
        }
    }

    var body: some View {
        let all = groups
        let new = all.filter(\.isNew)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get more from shukr").font(.system(.title2, design: .rounded, weight: .heavy))
                    Text("What shukr can do beyond the basics. Tap one to see what's inside.")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                if !new.isEmpty { section("New", note: "opening it clears the badge", new) }
                section("Beyond the app", note: "your iPhone and watch", all.filter { !$0.id.insideShukr && !$0.isNew })
                section("Inside shukr", note: "", all.filter { $0.id.insideShukr && !$0.isNew })
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
            if let raw = UserDefaults.standard.string(forKey: "demoExploreGroup"), let id = ExploreGroupID(rawValue: raw) {
                demoGroup = groups.first { $0.id == id }
            }
            #endif
        }
        .navigationDestination(item: $demoGroup) { ExploreGroupPage(group: $0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load(context: context) }
        }
    }

    @ViewBuilder private func section(_ title: String, note: String, _ groups: [ExploreGroup]) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    if !note.isEmpty { Text(note).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 4)
                // Wide cards like the original page (owner), a row that snaps card by card; the next one peeks in from the
                // right so there's clearly more.
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(groups) { group in
                            NavigationLink { destination(group) } label: { GroupCard(group: group) }
                                .buttonStyle(.plain)
                                .containerRelativeFrame(.horizontal) { width, _ in groups.count > 1 ? width - 28 : width }   // width: the row less its margins
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .padding(.horizontal, -16)
            }
        }
    }

    /// One member: straight to its story. More: the group's list.
    @ViewBuilder private func destination(_ group: ExploreGroup) -> some View {
        if group.members.count == 1, let only = group.members.first { ShowcaseStoryPage(card: only) }
        else { ExploreGroupPage(group: group) }
    }
}

private struct GroupCard: View {
    let group: ExploreGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShowcasePicture(id: group.id.picture, scale: 1.25)
                .frame(height: 180).frame(maxWidth: .infinity).clipped()
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.id.title)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                    Text(group.id.line)
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                status
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        let new = group.isNew, done = group.complete
        Text(new ? "New" : group.status)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(new ? Color.white : done ? Color.secondary : Color.sage)
            .padding(.horizontal, done && !new ? 0 : 8).padding(.vertical, 3)
            .background(Capsule().fill(new ? Color.sage : done ? Color.clear : Color.sage.opacity(0.14)))
    }
}

// MARK: - A group

struct ExploreGroupPage: View {
    let group: ExploreGroup
    /// DEBUG `-demoExploreMember siriMosques` (with `-demoExploreGroup`): that member's story, pushed (screenshots).
    @State private var demoMember = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ShowcasePicture(id: group.id.picture, big: true)
                    .frame(height: 240).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.id.title).font(.system(.title2, design: .rounded, weight: .heavy))
                    Text(group.id.lead).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(group.found == 0 ? "None \(group.id.doneWord) yet" : group.status).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(group.complete ? Color.secondary : Color.sage)
                        .padding(.top, 2)
                }
                VStack(spacing: 0) {
                    ForEach(Array(group.members.enumerated()), id: \.element.id) { i, member in
                        if i > 0 { Divider().padding(.leading, 76) }
                        NavigationLink { ExploreStoryPager(group: group, start: i) } label: { row(member) }
                            .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        #if DEBUG
        .task { demoMember = demoMemberCard != nil }
        .navigationDestination(isPresented: $demoMember) {
            if let c = demoMemberCard, let i = group.members.firstIndex(of: c) { ExploreStoryPager(group: group, start: i) }
        }
        #endif
    }

    #if DEBUG
    private var demoMemberCard: ShowcaseCard? {
        UserDefaults.standard.string(forKey: "demoExploreMember").flatMap { raw in group.members.first { $0.id.rawValue == raw } }
    }
    #endif

    private func row(_ member: ShowcaseCard) -> some View {
        HStack(spacing: 12) {
            ShowcasePicture(id: member.id, thumb: true)
                .frame(width: 124, height: 124)
                .scaleEffect(0.42)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // What it does, in a line (owner: "Today's Prayers" here and "Today's Times" in Shortcuts weren't clear from the
            // names; "See how" / "Tried" said nothing — the ✓ on the right says that).
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.id.memberName).font(.system(.body, design: .rounded))
                    if member.isNew {
                        Text("New").font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.sage))
                    }
                }
                Text(member.id.memberLine)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: member.using ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20)).foregroundStyle(member.using ? Color.sage : Color.secondary.opacity(0.5))
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - A group's members, one after another

/// A group's stories as pages (owner, decision explore-story-next D): swipe to the next, or tap its card at the foot. The
/// neighbours peek in at both edges and dots sit at the bottom (owner: "it doesn't look clear that we can scroll … like how
/// you had in option A").
struct ExploreStoryPager: View {
    let group: ExploreGroup
    @State private var current: ShowcaseCardID?
    @Environment(\.dismiss) private var dismiss
    /// How much of each neighbour shows, and the gap to it.
    private static let peek: CGFloat = 14, gap: CGFloat = 10

    init(group: ExploreGroup, start: Int) {
        self.group = group
        _current = State(initialValue: group.members.indices.contains(start) ? group.members[start].id : group.members.first?.id)
    }

    private var index: Int { group.members.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        let members = group.members
        ScrollView(.horizontal) {
            LazyHStack(spacing: Self.gap) {
                ForEach(Array(members.enumerated()), id: \.element.id) { i, member in
                    ShowcaseStoryPage(card: member, next: i + 1 < members.count ? members[i + 1] : nil, backTitle: group.id.title,
                                      onNext: {
                                          if i + 1 < members.count { withAnimation(.snappy(duration: 0.4)) { current = members[i + 1].id } }
                                          else { dismiss() }
                                      },
                                      marksOpened: false, sideInset: 0)
                        .safeAreaPadding(.bottom, 34)   // the page's own scroll ends clear of the dots
                        .containerRelativeFrame(.horizontal)
                        .id(member.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Self.peek + Self.gap, for: .scrollContent)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if members.count > 1 { dots(members.count) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if members.count > 1 {
                ToolbarItem(placement: .principal) {
                    Text("\(index + 1) of \(members.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { markOpened() }
        .onChange(of: current) { _, _ in markOpened() }
    }

    /// The page dots, on a small solid capsule so they read over the page's text (glass let it show through).
    private func dots(_ count: Int) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.sage : Color.secondary.opacity(0.35))
                    .frame(width: i == index ? 8 : 6, height: i == index ? 8 : 6)
            }
        }
        .animation(.snappy(duration: 0.25), value: index)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)).shadow(color: .black.opacity(0.12), radius: 6, y: 2))
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }

    private func markOpened() {
        guard let current else { return }
        UserDefaults.standard.set(true, forKey: ExploreShowcase.openedKey(current))
    }
}
