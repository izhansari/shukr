//
//  WhatsNewLists.swift
//  shukr
//
//  Two plain lists pushed from the top of What's new (owner, 2026-09-28: "where do i go … to see my
//  feedback? … it gets hidden after i respond" / "a link … to see changes in chronological order"):
//  - Your feedback: every note you've left, newest first, whatever its state (closed ones greyed,
//    never gone). Tap → that card, scrolled to its Feedback section.
//  - All changes: every live change, newest first, by day. Tap → that card, scrolled to the change.
//

import SwiftUI

struct YourFeedbackView: View {
    let go: (WhatsNewRoute) -> Void
    @State private var feedback = FeedbackStore.shared
    @State private var search = ""

    private var notes: [FeedbackItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return feedback.items
            .filter { item in
                q.isEmpty || item.text.localizedCaseInsensitiveContains(q) || cardTitle(item).localizedCaseInsensitiveContains(q)
            }
            .sorted { $0.updated > $1.updated }
    }

    private func cardTitle(_ item: FeedbackItem) -> String { WhatsNew.card(id: item.topic)?.title ?? item.topicTitle }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                let list = notes
                ForEach(list) { row($0) }
                if list.isEmpty {
                    Text(search.isEmpty ? "No feedback yet. Leave a 👍, 👎 or a note on any card." : "Nothing matches.")
                        .font(.subheadline).fontWeight(.light).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle("Your feedback")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search your feedback")
    }

    private func row(_ item: FeedbackItem) -> some View {
        let state = feedback.state(item)
        let done = !state.isOpen
        return Button { go(.cardAt(item.topic, focus: "feedback")) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(item.kind.color)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(cardTitle(item))
                        .font(.caption.weight(.medium)).foregroundStyle(Color.sage)
                    Text(item.text.isEmpty ? item.kind.label : item.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(WhatsNew.whenLabel(item.updated)) · \(feedback.stateLine(item, state))")
                        .font(.caption).foregroundStyle(tone(state))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .opacity(done ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Addressed notes want your eye; the rest are quiet.
    private func tone(_ state: FeedbackState) -> Color {
        if case .toCheck = state { return .green }
        return .secondary
    }
}

struct AllChangesView: View {
    /// Changes nobody has tested or given feedback on yet (a green dot).
    let untested: Set<String>
    let go: (WhatsNewRoute) -> Void
    @State private var search = ""

    private var days: [(day: Date, entries: [WhatsNewEntry])] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let list = WhatsNew.entries
            .filter(\.live)
            .filter { e in
                q.isEmpty || e.title.localizedCaseInsensitiveContains(q) || cardTitle(e).localizedCaseInsensitiveContains(q)
            }
            .sorted { $0.when > $1.when }
        let cal = Calendar.current
        var out: [(day: Date, entries: [WhatsNewEntry])] = []
        for e in list {
            let d = cal.startOfDay(for: e.when)
            if out.last?.day == d { out[out.count - 1].entries.append(e) } else { out.append((d, [e])) }
        }
        return out
    }

    private func cardTitle(_ e: WhatsNewEntry) -> String { WhatsNew.card(id: e.topic)?.title ?? e.topic }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20, pinnedViews: []) {
                let groups = days
                ForEach(groups, id: \.day) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(dayTitle(group.day))
                            Text("\(group.entries.count)").foregroundStyle(.quaternary)
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(1.4).textCase(.uppercase)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, entry in
                                if i > 0 { Divider().padding(.leading, 14) }
                                row(entry)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }
                }
                if groups.isEmpty {
                    Text("Nothing matches.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .fontDesign(.rounded)
        .navigationTitle("All changes")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search changes")
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func row(_ entry: WhatsNewEntry) -> some View {
        Button { go(.cardAt(entry.topic, focus: entry.id)) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if untested.contains(entry.id) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                        }
                        Text(entry.commit == "next" ? "this build" : entry.when.formatted(date: .omitted, time: .shortened))
                            .monospacedDigit()
                        Text("·")
                        Text(cardTitle(entry)).foregroundStyle(Color.sage)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(entry.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if let shot = entry.shots?.first {
                    ShotThumb(name: shot)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A screenshot's thumbnail, decoded off the main thread when the row appears.
private struct ShotThumb: View {
    let name: String
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .task(id: name) {
                let name = name
                image = await Task.detached(priority: .utility) {
                    guard let full = WhatsNew.image(name), full.size.width > 0, full.size.height > 0 else { return nil }
                    let scale = 132 / min(full.size.width, full.size.height)    // the short side fills 44 pt @3x
                    return full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale))
                }.value
            }
    }
}
