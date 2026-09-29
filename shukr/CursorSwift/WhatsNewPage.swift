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
    case page(String)
}

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = FeedbackStore.shared
    @State private var path: [WhatsNewRoute]
    @State private var answersOpen = false
    @State private var search = ""
    @State private var daysShown = 4
    @State private var composing: Compose?
    @State private var sharing: [FeedbackItem]?
    @State private var askMarkSent: [FeedbackItem]?
    /// "Saved · Add a comment" after a one-tap Works.
    @State private var justSaved: FeedbackItem?

    /// `startCard`: a change's id to open on (the "‹ What's new" pill).
    init(startCard: String? = nil) {
        _path = State(initialValue: startCard.map { [.change($0)] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(BuildInfo.line).font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
                    AnswersRow(open: $answersOpen, send: { sharing = feedback.unsent },
                               edit: { item in edit(item) }, everything: { path.append(.said) })
                    asksSection
                    changesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .fontDesign(.rounded)
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
                case .page(let link):
                    pushedPage(link)
                }
            }
            #if DEBUG
            .task { debugArgs() }
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

    private var asksSection: some View {
        let open = WhatsNew.openAsks()
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: "Your asks", count: open.count)
                Text(open.isEmpty ? "Nothing waiting for you." : "Built for you. Is it right?")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            ForEach(open, id: \.ask.id) { item in
                AskCard(ask: item.ask, latest: item.latest,
                        works: { works(item.ask, item.latest) },
                        notYet: { composing = Compose(entry: item.latest, ask: item.ask, kind: .issue) },
                        openChange: { path.append(.change(item.latest.id)) })
                    .transition(.asymmetric(insertion: .opacity, removal: .scale(scale: 0.96).combined(with: .opacity)))
            }
        }
        .animation(.snappy, value: open.map(\.ask.id))
    }

    private func works(_ ask: WhatsNewAsk, _ latest: WhatsNewEntry) {
        let item = feedback.save(existing: feedback.editableAnswer(ask: ask.id, entry: latest.id), entry: latest,
                                 ask: ask.id, kind: .works, text: "", media: [])
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
        guard let e = item.onEntry.flatMap(WhatsNew.entry) else { return }
        composing = Compose(entry: e, ask: item.ask.flatMap(WhatsNew.ask), kind: item.kind, existing: item)
    }

    // MARK: Every change

    private var days: [(day: Date, entries: [WhatsNewEntry])] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let list = WhatsNew.entries.reversed().filter { e in
            e.live && (q.isEmpty || e.title.localizedCaseInsensitiveContains(q) || (e.headline ?? "").localizedCaseInsensitiveContains(q)
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
        let shown = search.isEmpty ? Array(all.prefix(daysShown)) : all
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Every change", count: WhatsNew.entries.filter(\.live).count).padding(.leading, 4)
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
            ForEach(shown, id: \.day) { group in
                Text(dayTitle(group.day))
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.leading, 4).padding(.top, 4)
                VStack(spacing: 0) {
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
            } else if search.isEmpty && all.count > daysShown {
                Button("Earlier days") { withAnimation(.snappy) { daysShown += 7 } }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.sage)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
        }
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
    private func debugArgs() {
        let d = UserDefaults.standard
        if d.bool(forKey: "demoWhatsNewAnswers") { answersOpen = true }
        if d.string(forKey: "demoWhatsNewPage") == "said" { path = [.said] }
        if let id = d.string(forKey: "demoWhatsNewTopic") { path = [.topic(id)] }
        if let id = d.string(forKey: "demoWhatsNewChange") { path = [.change(id)] }
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
    let entry: WhatsNewEntry
    let ask: WhatsNewAsk?
    var kind: FeedbackItem.Kind = .issue
    var existing: FeedbackItem? = nil
    var id: String { "\(entry.id)|\(ask?.id ?? "-")|\(existing?.id.uuidString ?? "new")" }
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
                    ForEach(pending) { item in AnswerCard(item: item, edit: item.onEntry == nil ? nil : { edit(item) }) }
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

private struct AskCard: View {
    let ask: WhatsNewAsk
    let latest: WhatsNewEntry
    let works: () -> Void
    let notYet: () -> Void
    let openChange: () -> Void
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
                        .frame(height: 150)
                        .overlay { if let image { Image(uiImage: image).resizable().scaledToFit().padding(6) } }
                }
                .buttonStyle(.plain)
                .task(id: shot) {
                    image = await Task.detached(priority: .userInitiated) { WhatsNew.image(shot)?.preparingForDisplay() }.value
                }
                .accessibilityLabel("Screenshot of the change")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(meta).font(.footnote).foregroundStyle(.secondary)
                Button(action: openChange) {
                    Text(latest.short).font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                if let look = latest.steps.first {
                    (Text("Look for ").fontWeight(.semibold).foregroundStyle(Color.sage) + Text(look))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
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
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                    }
                    Button(action: notYet) {
                        Label("Not yet", systemImage: "pencil")
                            .font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
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
    }

    private var meta: String {
        var parts = [WhatsNew.area(latest.topic), ask.fromNote ? "your note" : "you asked in chat"]
        if attempt > 1 { parts.append("try \(attempt)") }
        parts.append(WhatsNew.whenLabel(latest.when))
        return parts.joined(separator: " · ")
    }
}

// MARK: - A row in Every change

private struct ChangeRow: View {
    let entry: WhatsNewEntry
    let tap: () -> Void
    var body: some View {
        let tag = WhatsNew.tag(for: entry)
        Button(action: tap) {
            HStack(spacing: 12) {
                Text(entry.when.formatted(date: .omitted, time: .shortened))
                    .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
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
                        Label("Add a comment", systemImage: "text.bubble")
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
                    if let ui = WhatsNew.image(name) {
                        Image(uiImage: ui).resizable().scaledToFit()
                            .frame(maxHeight: 360)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                            .opacity(entry.superseded ? 0.5 : 1)
                            .onTapGesture { viewing = ui }
                    }
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
