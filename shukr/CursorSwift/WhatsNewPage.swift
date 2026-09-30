//
//  WhatsNewPage.swift
//  shukr
//
//  What's new v4's page (owner-approved mockup, 2026-09-29):
//  - Your answers: one row at the top (Send · ⌄); open it to see everything he said that the team hasn't
//    read yet (and what they picked up in the last day), each with Edit. Nothing he says disappears.
//  - Your asks: things he asked for that were built. A big picture, what changed, "Look for", his words,
//    Works / Not yet. Answering moves it out (a newer change on the same ask brings it back).
//  - Every change: the log, newest first, by day, searchable; tap → the change (pictures, try it, his
//    words and answer, comments, Open in shukr, the feature's other changes).
//

import SwiftUI

enum WhatsNewRoute: Hashable {
    case change(String)
    case topic(String)
    case said
    case nextBuild
    case decisions
    case page(String)
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = FeedbackStore.shared
    @State private var path: [WhatsNewRoute]
    @State private var answersOpen = false
    @State private var search = ""
    /// What the list filters by: the search, 150 ms after the last keystroke (ask wn-speed).
    @State private var query = ""
    /// Cards he set aside for later (ask wn-speed): ask id → the change it was set aside on. A newer
    /// change on that ask brings the card back. Per phone.
    @AppStorage("whatsNew.later") private var laterRaw = ""
    /// Set-aside cards opened in place (this visit only).
    @State private var laterOpen: Set<String> = []
    /// Every change's area chip (nil = All).
    @State private var areaFilter: String?
    /// Your asks: grouped by area, or one list newest first (ask wn-asks-view); and the areas he folded.
    @AppStorage("whatsNew.asksByArea") private var asksByArea = true
    @AppStorage("whatsNew.foldedAreas") private var foldedAreasRaw = ""
    @State private var daysShown = 4
    @State private var composing: Compose?
    @State private var sharing: [FeedbackItem]?
    @State private var askMarkSent: [FeedbackItem]?
    /// "Saved · Add a comment" after a one-tap Works.
    @State private var justSaved: FeedbackItem?

    /// `startCard`: a change's id to open on (the "‹ What's new" pill).
    init(startCard: String? = nil) {
        _path = State(initialValue: startCard.map { [.change($0)] } ?? [])
        #if DEBUG
        if WhatsNewPerf.opened == 0 { WhatsNewPerf.opened = CACurrentMediaTime(); WhatsNewPerf.reset() }
        #endif
    }

    var body: some View {
        #if DEBUG
        let _ = WhatsNewPerf.body += 1
        #endif
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text(BuildInfo.line).font(.footnote).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        // An idea that isn't about a card (ask wn-ideas).
                        Button { composing = Compose(entry: nil, ask: nil, kind: .idea) } label: {
                            Label("New idea", systemImage: "lightbulb")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Color.sage)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 4)
                    AnswersRow(open: $answersOpen, send: { sharing = feedback.unsent },
                               edit: { item in edit(item) }, everything: { path.append(.said) })
                    NextBuildRow { path.append(.nextBuild) }
                    asksSection
                    changesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .fontDesign(.rounded)
            .task(id: search) {
                if search.isEmpty { query = ""; return }
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { query = search }
            }
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Decisions waiting for him: a badge top right (ask wn-decisions); nothing at 0.
                ToolbarItem(placement: .topBarTrailing) {
                    DecisionsBadgeButton(count: WhatsNew.openDecisions().count) { path.append(.decisions) }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay(alignment: .bottom) { savedToast }
            .navigationDestination(for: WhatsNewRoute.self) { route in
                switch route {
                case .change(let id):
                    if let e = WhatsNew.entry(id) {
                        ChangeDetailView(entry: e, compose: { composing = $0 }, open: opener(for: e),
                                         topic: { path.append(.topic($0)) })
                    }
                case .topic(let id):
                    TopicChangesView(topic: id) { path.append(.change($0)) }
                case .said:
                    EverythingSaidView { path.append(.change($0)) }
                case .decisions:
                    DecisionsView()
                case .nextBuild:
                    NextBuildView { path.append(.change($0)) }
                case .page(let link):
                    pushedPage(link)
                }
            }
            #if DEBUG
            .task { debugArgs() }
            .task { await perfRun() }
            #endif
        }
        .onAppear {
            feedback.reloadReceived()
            WhatsNewReturn.shared.card = nil      // opened (any way): the pill has done its job
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-whatsNewDump") { dump() }
            #endif
        }
        .sheet(item: $composing) { c in
            NoteComposer(entry: c.entry, ask: c.ask, startKind: c.kind, existing: c.existing) { _ in }
                .presentationDetents([.large])
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

    // MARK: Your asks

    private var later: [String: String] {
        guard let data = laterRaw.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }
    private func setLater(_ ask: WhatsNewAsk, _ latest: WhatsNewEntry, _ on: Bool) {
        var map = later
        map[ask.id] = on ? latest.id : nil
        // Only asks still waiting on that change are worth remembering.
        let open = Set(WhatsNew.openAsks().map { "\($0.ask.id)|\($0.latest.id)" })
        map = map.filter { open.contains("\($0.key)|\($0.value)") }
        laterRaw = (try? String(data: JSONEncoder().encode(map), encoding: .utf8)) ?? ""
    }
    private func isLater(_ item: (ask: WhatsNewAsk, latest: WhatsNewEntry)) -> Bool { later[item.ask.id] == item.latest.id }

    private var asksSection: some View {
        let all = WhatsNew.openAsks()
        let open = all.filter { !isLater($0) }
        let aside = all.filter { isLater($0) }
        let groups = Dictionary(grouping: open) { WhatsNew.area($0.latest.topic) }
            .sorted { WhatsNew.areaRank($0.key) < WhatsNew.areaRank($1.key) }
        let grouped = asksByArea && groups.count > 1
        return LazyVStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center) {
                    SectionTitle(text: "Your asks", count: open.count)
                    Spacer(minLength: 8)
                    if open.count > 1 { asksViewToggle }
                }
                Group {
                    if !open.isEmpty {
                        Text("Built for you. Is it right?")
                    } else if aside.isEmpty {
                        Text("All caught up ✓")
                    } else {
                        Text("Nothing left to test from here · \(aside.count) set aside")
                    }
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            if grouped {
                // Groups inside Your asks, not peers of it: sentence case, indented, a chevron to fold.
                ForEach(groups, id: \.key) { group in
                    let folded = foldedAreas.contains(group.key)
                    AreaGroupHeader(area: group.key, count: group.value.count, folded: folded) {
                        withAnimation(.snappy) { toggleFold(group.key) }
                    }
                    if !folded {
                        ForEach(group.value, id: \.ask.id) { askCard($0) }
                    }
                }
            } else {
                ForEach(open, id: \.ask.id) { askCard($0) }
            }
            if !aside.isEmpty {
                // Set aside for later: one line each, under the open ones.
                Text("Set aside · \(aside.count)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4).padding(.top, 6)
                ForEach(aside, id: \.ask.id) { item in
                    if laterOpen.contains(item.ask.id) {
                        askCard(item, folded: true)
                    } else {
                        LaterRow(ask: item.ask, latest: item.latest) {
                            withAnimation(.snappy) { _ = laterOpen.insert(item.ask.id) }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func askCard(_ item: (ask: WhatsNewAsk, latest: WhatsNewEntry), folded: Bool = false) -> some View {
        AskCard(ask: item.ask, latest: item.latest, setAside: folded,
                works: { works(item.ask, item.latest) },
                notYet: { composing = Compose(entry: item.latest, ask: item.ask, kind: .issue) },
                openChange: { path.append(.change(item.latest.id)) },
                later: {
                    triggerSomeVibration(type: .light)
                    withAnimation(.snappy) {
                        if folded { _ = laterOpen.remove(item.ask.id) }   // back to its one line
                        else { setLater(item.ask, item.latest, true) }
                    }
                })
            .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.96).combined(with: .opacity)))
    }

    /// "By area" ⇄ "Newest first" (remembered).
    private var asksViewToggle: some View {
        Button {
            triggerSomeVibration(type: .light)
            withAnimation(.snappy) { asksByArea.toggle() }
        } label: {
            Label(asksByArea ? "By area" : "Newest first", systemImage: asksByArea ? "square.grid.2x2" : "clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sage)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.sage.opacity(0.14)))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Switches between grouping by area and newest first")
    }

    private var foldedAreas: Set<String> {
        Set(foldedAreasRaw.split(separator: "|").map(String.init))
    }
    private func toggleFold(_ area: String) {
        var s = foldedAreas
        if s.contains(area) { s.remove(area) } else { s.insert(area) }
        foldedAreasRaw = s.sorted().joined(separator: "|")
    }

    private func works(_ ask: WhatsNewAsk, _ latest: WhatsNewEntry) {
        let item = withAnimation(.snappy) {
            feedback.save(existing: feedback.editableAnswer(ask: ask.id, entry: latest.id), entry: latest,
                          ask: ask.id, kind: .works, text: "", media: [])
        }
        triggerSomeVibration(type: .success)
        withAnimation(.snappy) { justSaved = item }
        Task {
            try? await Task.sleep(for: .seconds(4))
            if justSaved?.id == item.id { withAnimation(.snappy) { justSaved = nil } }
        }
    }

    @ViewBuilder private var savedToast: some View {
        if let item = justSaved {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                Text("Saved: works").font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Button("Add a comment") {
                    justSaved = nil
                    edit(item)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.sage)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
            .padding(.horizontal, 16).padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func edit(_ item: FeedbackItem) {
        let e = item.onEntry.flatMap(WhatsNew.entry)
        guard e != nil || item.kind == .idea else { return }     // a v1–v3 note isn't edited here
        composing = Compose(entry: e, ask: item.ask.flatMap(WhatsNew.ask), kind: item.kind, existing: item)
    }

    // MARK: Every change

    private var days: [(day: Date, entries: [WhatsNewEntry])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = WhatsNew.entries.reversed().filter { e in
            e.live && (areaFilter == nil || WhatsNew.area(e.topic) == areaFilter) && (q.isEmpty || e.title.localizedCaseInsensitiveContains(q) || (e.headline ?? "").localizedCaseInsensitiveContains(q)
                       || WhatsNew.topicTitle(e.topic).localizedCaseInsensitiveContains(q)
                       || WhatsNew.area(e.topic).localizedCaseInsensitiveContains(q))
        }
        var out: [(day: Date, entries: [WhatsNewEntry])] = []
        let cal = Calendar.current
        for e in list {
            let d = cal.startOfDay(for: e.when)
            if out.last?.day == d { out[out.count - 1].entries.append(e) } else { out.append((d, [e])) }
        }
        return out
    }

    private var changesSection: some View {
        let all = days
        let narrowed = !query.isEmpty || areaFilter != nil
        let shown = narrowed ? all : Array(all.prefix(daysShown))
        return VStack(alignment: .leading, spacing: 10) {
            // The count follows the chip and the search (owner: "sure to filter totals").
            SectionTitle(text: "Every change", count: all.reduce(0) { $0 + $1.entries.count }).padding(.leading, 4)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search changes, e.g. widget", text: $search)
                    .textInputAutocapitalization(.never)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
            areaChips
            ForEach(shown, id: \.day) { group in
                Text(dayTitle(group.day))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4).padding(.top, 4)
                LazyVStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().padding(.leading, 82) }
                        ChangeRow(entry: e) { path.append(.change(e.id)) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            if all.isEmpty {
                Text("Nothing matches.").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if !narrowed && all.count > daysShown {
                Button("Earlier days") { withAnimation(.snappy) { daysShown += 7 } }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
        }
    }

    /// "All" and each area that has changes, in the page's order. Clipped like any ScrollView — never
    /// `scrollClipDisabled` here (a horizontal ScrollView let this page move sideways once, BA0ECB7A).
    private var areaChips: some View {
        let present = Set(WhatsNew.entries.filter(\.live).map { WhatsNew.area($0.topic) })
        let areas = present.sorted { (WhatsNew.areaRank($0), $0) < (WhatsNew.areaRank($1), $1) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                areaChip("All", on: areaFilter == nil) { areaFilter = nil }
                ForEach(areas, id: \.self) { area in
                    areaChip(area, on: areaFilter == area) { areaFilter = areaFilter == area ? nil : area }
                }
            }
        }
    }

    private func areaChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.sage : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color(.tertiarySystemFill)))
                // A 44 pt tall tap target round the same-looking chip (owner: "sure to tap area").
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: Open in shukr

    private func opener(for entry: WhatsNewEntry) -> (() -> Void)? {
        guard let link = WhatsNew.topic(entry.topic)?.link, WhatsNew.links.contains(link) else { return nil }
        return {
            if WhatsNew.pushable.contains(link) {
                path.append(.page(link))                  // ‹ Back returns to the change
                return
            }
            WhatsNewReturn.shared.card = entry.id         // the pill reopens it here
            dismiss()
            NotificationCenter.default.post(name: WhatsNew.go, object: link)
        }
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

    #if DEBUG
    /// `-demoWhatsNewChange <id>` · `-demoWhatsNewTopic <id>` · `-demoWhatsNewPage said` ·
    /// `-demoWhatsNewAnswers` (the row open) · `-demoWhatsNewCompose <change id>` (answering its ask, or a comment).
    /// DEBUG `-whatsNewPerf`: the open time, then three letters typed in search, then one area folded.
    private func perfRun() async {
        guard WhatsNewPerf.on else { return }
        let ms = (CACurrentMediaTime() - WhatsNewPerf.opened) * 1000
        WhatsNewPerf.runs += 1
        print(String(format: "WNPERF open #%d%@: %.0f ms to the first frame", WhatsNewPerf.runs, WhatsNewPerf.runs == 1 ? " (cold, 1 s after launch)" : " (warm)", ms))
        WhatsNewPerf.report("open")
        guard WhatsNewPerf.runs == 1 else { return }
        try? await Task.sleep(for: .seconds(1.5))
        WhatsNewPerf.reset()
        for letter in ["w", "i", "d"] {
            search += letter
            try? await Task.sleep(for: .seconds(0.4))
        }
        WhatsNewPerf.report("search 3 letters")
        search = ""
        try? await Task.sleep(for: .seconds(1))
        WhatsNewPerf.reset()
        let firstArea = Dictionary(grouping: WhatsNew.openAsks()) { WhatsNew.area($0.latest.topic) }.keys
            .sorted { WhatsNew.areaRank($0) < WhatsNew.areaRank($1) }.first
        WhatsNewPerf.reset()
        if let firstArea { withAnimation(.snappy) { toggleFold(firstArea) } }
        try? await Task.sleep(for: .seconds(0.8))
        WhatsNewPerf.report("fold one area")
        if let firstArea { toggleFold(firstArea) }
        try? await Task.sleep(for: .seconds(1))
        NotificationCenter.default.post(name: WhatsNewPerf.reopen, object: nil)
    }

    private func debugArgs() {
        // `-demoWhatsNewAllLater`: every open card set aside (the "Nothing left to test" screenshot);
        // `-demoWhatsNewNoLater`: none.
        if ProcessInfo.processInfo.arguments.contains("-demoWhatsNewAllLater") {
            let map = Dictionary(WhatsNew.openAsks().map { ($0.ask.id, $0.latest.id) }, uniquingKeysWith: { a, _ in a })
            laterRaw = (try? String(data: JSONEncoder().encode(map), encoding: .utf8)) ?? ""
        }
        if ProcessInfo.processInfo.arguments.contains("-demoWhatsNewNoLater") { laterRaw = "" }
        let d = UserDefaults.standard
        if d.bool(forKey: "demoWhatsNewAnswers") { answersOpen = true }
        if d.string(forKey: "demoWhatsNewPage") == "said" { path = [.said] }
        if d.string(forKey: "demoWhatsNewPage") == "next" { path = [.nextBuild] }
        if d.string(forKey: "demoWhatsNewPage") == "decisions" { path = [.decisions] }
        if let id = d.string(forKey: "demoWhatsNewTopic") { path = [.topic(id)] }
        if let id = d.string(forKey: "demoWhatsNewChange") { path = [.change(id)] }
        // `-demoWhatsNewIdea`: the header's New idea · `-demoWhatsNewIdeaFrom <change id>`: an idea from that card
        // (`-demoIdeaText` / `-demoIdeaArea` fill it in).
        if d.object(forKey: "demoWhatsNewIdea") != nil { composing = Compose(entry: nil, ask: nil, kind: .idea) }
        if let id = d.string(forKey: "demoWhatsNewIdeaFrom"), let e = WhatsNew.entry(id) {
            composing = Compose(entry: e, ask: nil, kind: .idea)
        }
        if let id = d.string(forKey: "demoWhatsNewCompose"), let e = WhatsNew.entry(id) {
            composing = Compose(entry: e, ask: e.askIDs.first.flatMap(WhatsNew.ask), kind: .issue)
        }
    }

    /// `-whatsNewDump`: every ask's state, for checking against pulled data.
    private func dump() {
        for a in WhatsNew.asks.sorted(by: { $0.id < $1.id }) {
            let s: String
            switch WhatsNew.status(of: a) {
            case .open(let l): s = "OPEN on \(l.id)"
            case .answered(let w, let l, let ans): s = "\(w ? "WORKS" : "NOTYET") on \(l.id) (\(ans.label))"
            case .gone: s = "GONE"
            }
            print("WNDUMP \(a.id) \(s)")
        }
        print("WNDUMP pending=\(feedback.pending.count) unsent=\(feedback.unsent.count) items=\(feedback.items.count)")
    }
    #endif
}

/// What the composer sheet opens on.
struct Compose: Identifiable {
    /// nil = a new idea from the page's header.
    let entry: WhatsNewEntry?
    let ask: WhatsNewAsk?
    var kind: FeedbackItem.Kind = .issue
    var existing: FeedbackItem? = nil
    var id: String { "\(entry?.id ?? "idea")|\(ask?.id ?? "-")|\(existing?.id.uuidString ?? "new")" }
}

/// An area's header inside Your asks: a sub-heading of it (sentence case, indented), with a chevron that
/// folds its cards and the count.
private struct AreaGroupHeader: View {
    let area: String
    let count: Int
    let folded: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(folded ? 0 : 90))
                Text(area)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                Text("\(count)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Color(.tertiarySystemFill)))
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(area), \(count) \(count == 1 ? "ask" : "asks")")
        .accessibilityHint(folded ? "Shows them" : "Hides them")
    }
}

struct SectionTitle: View {
    let text: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(text)
            if let count { Text("· \(count)") }
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .tracking(1.2).textCase(.uppercase)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Your answers (the row at the top)

private struct AnswersRow: View {
    @Binding var open: Bool
    let send: () -> Void
    let edit: (FeedbackItem) -> Void
    let everything: () -> Void
    @State private var feedback = FeedbackStore.shared

    var body: some View {
        let pending = feedback.pending
        let unsent = feedback.unsent
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pending.isEmpty ? "Your answers" : "Your answers · \(pending.count)")
                            .font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text(summary(pending)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: send) {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(unsent.isEmpty ? Color.secondary : Color.green)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(unsent.isEmpty ? Color(.tertiarySystemFill) : Color.green.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .disabled(unsent.isEmpty)
                Button { withAnimation(.snappy) { open.toggle() } } label: {
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Hide your answers" : "Show your answers")
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pending) { item in
                        // A v3 note isn't edited here, nor a Ready for TestFlight note (nothing to edit).
                        AnswerCard(item: item, edit: item.isV3Note || item.kind == .ship ? nil : { edit(item) })
                    }
                    if pending.isEmpty {
                        Text("The team has read everything you've said.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.leading, 4)
                    }
                    Button(action: everything) {
                        Text("Everything you've said · \(feedback.items.count) ›")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func summary(_ pending: [FeedbackItem]) -> String {
        guard !pending.isEmpty else { return "All read by the team" }
        var saved = 0, sent = 0, have = 0
        for i in pending {
            switch feedback.state(i) {
            case .saved: saved += 1
            case .sent: sent += 1
            case .received: have += 1
            }
        }
        var parts: [String] = []
        if saved > 0 { parts.append("\(saved) saved on this phone") }
        if sent > 0 { parts.append("\(sent) sent") }
        if have > 0 { parts.append("\(have) Bradley has") }
        return parts.joined(separator: " · ")
    }
}

/// One thing he said, in full: what it's about, the answer, his words, his photos / videos, where it stands.
struct AnswerCard: View {
    let item: FeedbackItem
    var edit: (() -> Void)? = nil
    @State private var feedback = FeedbackStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let shot = item.onEntry.flatMap(WhatsNew.entry)?.shots?.first { ShotThumb(name: shot) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.about).font(.body.weight(.semibold)).lineLimit(2)
                    HStack(spacing: 6) {
                        VerdictChip(kind: item.kind)
                        Text(WhatsNew.whenLabel(item.updated)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let edit {
                    Button("Edit", action: edit)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.sage)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            if !item.text.isEmpty {
                Text(item.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            if !item.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.attachments.prefix(5), id: \.self) { MediaThumb(name: $0).frame(width: 52, height: 52) }
                    if item.attachments.count > 5 {
                        Text("+\(item.attachments.count - 5)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(feedback.stateLine(item))
            }
            .font(.footnote).foregroundStyle(dot == .green ? Color.green : .secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var dot: Color {
        switch feedback.state(item) {
        case .saved: Color(.systemGray3)
        case .sent: .sage
        case .received: .green
        }
    }
}

struct VerdictChip: View {
    let kind: FeedbackItem.Kind
    var body: some View {
        Text(kind.label)
            .font(.caption.weight(.bold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(kind.color.opacity(0.14)))
    }
}

// MARK: - An ask's card

/// The size rule (ask wn-speed — owner: "clearly there was no rule to stop it from taking up the whole
/// page"): an ask card is at most ~40 % of the screen — picture 110 pt, headline 2 lines, "Look for" 2
/// lines, his words folded, buttons 40 pt. A change row is 1–2 lines; Next build one line.
private struct AskCard: View {
    let ask: WhatsNewAsk
    let latest: WhatsNewEntry
    /// Set aside for later and opened in place: the fold closes it back to its one line.
    var setAside = false
    let works: () -> Void
    let notYet: () -> Void
    let openChange: () -> Void
    /// The fold (top right): "Later" — the card drops to one line under the open ones.
    let later: () -> Void
    @State private var wordsOpen = false
    @State private var image: UIImage?

    private var attempt: Int { WhatsNew.entries(ask: ask.id).count }
    private var words: String {
        if let w = ask.words, !w.isEmpty { return w }
        // A note's words live on the phone when the pull didn't have them.
        let prefix = ask.note?.lowercased() ?? "-"
        return FeedbackStore.shared.items.first { $0.id.uuidString.lowercased().hasPrefix(prefix) }?.text ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let shot = latest.shots?.first {
                Button(action: openChange) {
                    Rectangle().fill(Color(.tertiarySystemFill).opacity(0.5))
                        .frame(height: 110)
                        .overlay { if let image { Image(uiImage: image).resizable().scaledToFit().padding(6) } }
                }
                .buttonStyle(.plain)
                .task(id: shot) {
                    image = await Task.detached(priority: .userInitiated) { WhatsNew.image(shot)?.preparingForDisplay() }.value
                }
                .accessibilityLabel("Screenshot of the change")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Button(action: later) {
                        Label(setAside ? "Fold" : "Later", systemImage: setAside ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                            // A 44 pt hit area round the same small capsule; the row doesn't grow.
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .padding(.vertical, -6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(setAside ? "Fold it again" : "Set aside for later")
                }
                Button(action: openChange) {
                    Text(latest.short).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                if let look = latest.steps.first {
                    (Text("Look for ").fontWeight(.semibold).foregroundStyle(Color.sage) + Text(look))
                        .font(.subheadline)
                        .lineLimit(2)
                }
                if !words.isEmpty {
                    if wordsOpen {
                        Text("\u{201C}\(words)\u{201D}")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                            .onTapGesture { withAnimation(.snappy) { wordsOpen = false } }
                    } else {
                        Button { withAnimation(.snappy) { wordsOpen = true } } label: {
                            Text("Your words ›").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 10) {
                    Button(action: works) {
                        Label("Works", systemImage: "checkmark")
                            .font(.body.weight(.semibold)).foregroundStyle(Color.green)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                    }
                    Button(action: notYet) {
                        Label("Not yet", systemImage: "pencil")
                            .font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(Color(.tertiarySystemFill)))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // An edge all round, so the picture reads as part of its card (owner, 2026-09-29).
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(.separator), lineWidth: 1))
    }

    private var meta: String {
        var parts = [WhatsNew.area(latest.topic), ask.fromNote ? "your note" : "you asked in chat"]
        if attempt > 1 { parts.append("try \(attempt)") }
        parts.append(WhatsNew.whenLabel(latest.when))
        return parts.joined(separator: " · ")
    }
}

/// A card set aside for later (ask wn-speed): one line — a 32 pt picture, the headline, the area. A tap
/// opens the full card in place (Works / Not yet); its fold closes it again.
private struct LaterRow: View {
    let ask: WhatsNewAsk
    let latest: WhatsNewEntry
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                if let shot = latest.shots?.first { ShotThumb(name: shot, size: 32) }
                else { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(.tertiarySystemFill)).frame(width: 32, height: 32) }
                Text(latest.short).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text(WhatsNew.area(latest.topic)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the card")
    }
}

// MARK: - Next build (ask wn-next-build)

/// "Next build · 14 changes since build 12 ›", under Your answers.
private struct NextBuildRow: View {
    let open: () -> Void
    var body: some View {
        let count = WhatsNew.sinceLastBuild.count
        let since = WhatsNew.lastBuild.map { "since build \($0.number)" } ?? "so far"
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox").font(.body).foregroundStyle(Color.sage)
                // One line (the size rule).
                (Text("Next build").font(.body.weight(.semibold)).foregroundStyle(.primary)
                 + Text(" · \(count) change\(count == 1 ? "" : "s") \(since)").font(.footnote).foregroundStyle(.secondary))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Everything since the last TestFlight upload, by area; how many of his asks in it still wait; and
/// "I'm happy with this — ready for TestFlight" (a note to the team: Frank confirms with him before
/// uploading, so it's never a gate and nothing uploads from here).
private struct NextBuildView: View {
    let openChange: (String) -> Void
    @State private var feedback = FeedbackStore.shared

    var body: some View {
        let changes = WhatsNew.sinceLastBuild
        let ids = Set(changes.map(\.id))
        // His asks whose newest change is in this build and still waits for an answer (newest first).
        let waiting = WhatsNew.openAsks().filter { ids.contains($0.latest.id) }
        let groups = Dictionary(grouping: changes.reversed()) { WhatsNew.area($0.topic) }
            .sorted { WhatsNew.areaRank($0.key) < WhatsNew.areaRank($1.key) }
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(WhatsNew.lastBuild.map { "Everything since build \($0.number), by area." } ?? "Everything so far, by area.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.leading, 4)
                    ForEach(groups, id: \.key) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: group.key, count: group.value.count).padding(.leading, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(group.value.enumerated()), id: \.element.id) { i, e in
                                    if i > 0 { Divider().padding(.leading, 82) }
                                    ChangeRow(entry: e) { openChange(e.id) }.id(e.id)
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                        }
                    }
                    if changes.isEmpty {
                        Text("Nothing new since the last build yet.").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    Button {
                        guard let first = waiting.first else { return }
                        withAnimation(.snappy) { proxy.scrollTo(first.latest.id, anchor: .center) }
                    } label: {
                        Text(waiting.isEmpty ? "Everything you asked for here is answered ✓"
                             : "\(waiting.count) of your asks in this build still need\(waiting.count == 1 ? "s" : "") your answer")
                            .font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.leading, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(waiting.isEmpty)
                    if let ready = feedback.readyForTestFlight {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Sent to the team", systemImage: "paperplane.fill").font(.subheadline.weight(.semibold))
                            Text("Frank confirms with you before uploading · \(WhatsNew.whenLabel(ready.created))")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(Color.sage)
                        .padding(.leading, 4)
                    }
                    Button {
                        feedback.saveReadyForTestFlight(changes: changes, openAsks: waiting.count)
                        triggerSomeVibration(type: .success)
                    } label: {
                        Text(feedback.readyForTestFlight == nil ? "I'm happy with this — ready for TestFlight" : "Send again (updated)")
                            .font(.body.weight(.semibold)).foregroundStyle(Color.sage)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Capsule().fill(Color.sage.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .disabled(changes.isEmpty)
                }
                .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle("Next build")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - A row in Every change

private struct ChangeRow: View {
    let entry: WhatsNewEntry
    let tap: () -> Void
    /// The time column: wide enough for "12:57 PM" and growing with the text size, so the rows stay
    /// lined up; the time itself never wraps (it did at 58 pt: "12:57 P" / "M").
    @ScaledMetric(relativeTo: .footnote) private var timeWidth: CGFloat = 64
    var body: some View {
        let tag = WhatsNew.tag(for: entry)
        Button(action: tap) {
            HStack(spacing: 12) {
                Text(entry.when.formatted(date: .omitted, time: .shortened))
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                    .frame(minWidth: timeWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(WhatsNew.area(entry.topic))
                        if let tag { Text("·"); Text(tag.text).fontWeight(.semibold).foregroundStyle(tag.tone) }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(entry.short).font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let shot = entry.shots?.first { ShotThumb(name: shot) }
                else { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(.tertiarySystemFill)).frame(width: 44, height: 44) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A change's picture, decoded off the main thread (ask wn-speed: it was decoded in `body`).
private struct DetailShot: View {
    let name: String
    let dimmed: Bool
    let tap: (UIImage) -> Void
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 360)
                    .onTapGesture { tap(image) }
            } else {
                Color.clear.frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .opacity(dimmed ? 0.5 : 1)
        .task(id: name) {
            image = await Task.detached(priority: .userInitiated) { WhatsNew.image(name)?.preparingForDisplay() }.value
        }
    }
}

// MARK: - One change

struct ChangeDetailView: View {
    let entry: WhatsNewEntry
    let compose: (Compose) -> Void
    var open: (() -> Void)? = nil
    let topic: (String) -> Void
    @State private var feedback = FeedbackStore.shared
    @State private var viewing: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                shots
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(WhatsNew.area(entry.topic)) · \(WhatsNew.whenLabel(entry.when))\(entry.superseded ? " · \(entry.status!)" : "")")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(entry.short).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if entry.headline != nil {
                        Text(entry.title).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(entry.askIDs.compactMap(WhatsNew.ask), id: \.id) { ask in askBox(ask) }
                if !entry.steps.isEmpty {
                    box("Try it") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(entry.steps.enumerated()), id: \.offset) { n, step in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(n + 1).").monospacedDigit().foregroundStyle(.tertiary)
                                    Text(step).fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button { compose(Compose(entry: entry, ask: nil, kind: .note)) } label: {
                        Label("Comment or idea", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                    }
                    if let open {
                        Button(action: open) {
                            Label("Open in shukr", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(Capsule().fill(Color.sage.opacity(0.14)))
                        }
                    }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.sage)
                .buttonStyle(.plain)
                let said = WhatsNew.said(on: entry)
                if !said.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "What you said").padding(.leading, 4)
                        ForEach(said) { item in
                            AnswerCard(item: item) { compose(Compose(entry: entry, ask: item.ask.flatMap(WhatsNew.ask), kind: item.kind, existing: item)) }
                        }
                    }
                }
                let count = WhatsNew.entries(topic: entry.topic).count
                Button { topic(entry.topic) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(WhatsNew.topicTitle(entry.topic)): every change").font(.body.weight(.semibold))
                            Spacer()
                            Text("\(count) ›").foregroundStyle(.secondary)
                        }
                        if let summary = WhatsNew.topic(entry.topic)?.summary {
                            Text(summary).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle(WhatsNew.area(entry.topic))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: Binding(get: { viewing.map(IdentifiedImage.init) }, set: { viewing = $0?.image })) {
            ZikrPhotoViewer(image: $0.image)
        }
    }

    /// Stacked and fitted to the column: never a sideways scroll (owner, BA0ECB7A).
    @ViewBuilder private var shots: some View {
        if let names = entry.shots, !names.isEmpty {
            VStack(spacing: 10) {
                ForEach(names, id: \.self) { name in
                    DetailShot(name: name, dimmed: entry.superseded) { viewing = $0 }
                }
            }
        }
    }

    private func askBox(_ ask: WhatsNewAsk) -> some View {
        let status = WhatsNew.status(of: ask)
        let isLatest: Bool = { if case .open(let l) = status { return l.id == entry.id }; if case .answered(_, let l, _) = status { return l.id == entry.id }; return false }()
        return box(ask.fromNote ? "Your note" : "You asked in chat") {
            VStack(alignment: .leading, spacing: 10) {
                if let w = ask.words, !w.isEmpty {
                    Text("\u{201C}\(w)\u{201D}").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                switch status {
                case .open where isLatest:
                    HStack(spacing: 10) {
                        Button {
                            FeedbackStore.shared.save(existing: nil, entry: entry, ask: ask.id, kind: .works, text: "", media: [])
                            triggerSomeVibration(type: .success)
                        } label: {
                            Label("Works", systemImage: "checkmark").foregroundStyle(Color.green)
                                .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(Color.green.opacity(0.14)))
                        }
                        Button { compose(Compose(entry: entry, ask: ask, kind: .issue)) } label: {
                            Label("Not yet", systemImage: "pencil").foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                    .font(.subheadline.weight(.semibold)).buttonStyle(.plain)
                case .answered(let works, _, let answer) where isLatest:
                    HStack(spacing: 8) {
                        Image(systemName: works ? "checkmark.circle.fill" : "pencil.circle.fill")
                            .foregroundStyle(works ? Color.green : Color.orange)
                        Text(answer.label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(works ? Color.green : Color.orange)
                        Spacer()
                        Button("Change my answer") {
                            var existing: FeedbackItem?
                            if case .phone(let item) = answer.source, feedback.state(item) == .saved { existing = item }
                            compose(Compose(entry: entry, ask: ask, kind: works ? .issue : .works, existing: existing))
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.sage)
                    }
                default:
                    Text(isLatest ? "" : "A newer change followed this one.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func box<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}

// MARK: - A feature's changes

struct TopicChangesView: View {
    let topic: String
    let go: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let t = WhatsNew.topic(topic) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t.area).font(.footnote).foregroundStyle(.secondary)
                        Text(t.title).font(.title2.weight(.semibold))
                        if let s = t.summary { Text(s).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                VStack(spacing: 0) {
                    let list = WhatsNew.entries(topic: topic).reversed()
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider().padding(.leading, 14) }
                        Button { go(e.id) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(WhatsNew.whenLabel(e.when) + (e.superseded ? " · \(e.status!)" : ""))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(e.short).font(.subheadline)
                                        .foregroundStyle(e.superseded ? .tertiary : .primary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                if let shot = e.shots?.first { ShotThumb(name: shot).opacity(e.superseded ? 0.5 : 1) }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle("Every change")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Everything you've said

struct EverythingSaidView: View {
    let go: (String) -> Void
    @State private var feedback = FeedbackStore.shared
    @State private var search = ""

    private var list: [FeedbackItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return feedback.items
            .filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) || $0.about.localizedCaseInsensitiveContains(q)
                      || $0.topicTitle.localizedCaseInsensitiveContains(q) }
            .sorted { $0.updated > $1.updated }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                let items = list
                ForEach(items) { item in
                    if let entry = item.onEntry {
                        Button { go(entry) } label: { AnswerCard(item: item) }.buttonStyle(.plain)
                    } else {
                        AnswerCard(item: item)          // a v1–v3 note (no change attached)
                    }
                }
                if items.isEmpty {
                    Text(search.isEmpty ? "Nothing yet." : "Nothing matches.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle("Everything you've said")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search what you've said")
    }
}

private struct IdentifiedImage: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}
