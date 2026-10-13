//
//  ExploreSimple.swift
//  shukr
//
//  Settings → Explore shukr, simple (owner 2026-10-13, ask settings-explore-lean: "I kind of liked how it was in the very
//  beginning, very simple, easy. If you click on it, then you can see everything that you want to see about it … I don't
//  want there to be scrolling. Horizontally"). Frank's original page's look (ExploreShukr.swift): one card per group down
//  the page — its picture, its name, one line — and nothing to count. A tap opens the group's page (ExploreGroupPage: its
//  members, each with its story) or, for a one-member group, the story itself; the detail lives there. The default; the
//  other pages stay in My Dev Stuff → Explore page.
//

import SwiftUI
import SwiftData

struct ExploreSimplePage: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("shukr beyond the app").font(.system(.title3, design: .rounded, weight: .semibold))
                    Text("Your prayers on your Lock Screen, your wrist and a swipe away. Tap one to see what it does.")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                ForEach(groups) { group in
                    NavigationLink { destination(group) } label: { SimpleGroupCard(group: group) }
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
            ExploreWidgetData.warm()   // the pictures' data, once, off the main thread
            await model.load(context: context)
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "demoExploreGroup"), let id = ExploreGroupID(rawValue: raw) {
                demoGroup = groups.first { $0.id == id }
            }
            #endif
        }
        .navigationDestination(item: $demoGroup) { destination($0) }
        // Back from the Home Screen or Control Center: what they just added shows as added inside.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load(context: context) }
        }
    }

    /// One member: straight to its story. More: the group's page.
    @ViewBuilder private func destination(_ group: ExploreGroup) -> some View {
        if group.members.count == 1, let only = group.members.first { ShowcaseStoryPage(card: only) }
        else { ExploreGroupPage(group: group) }
    }
}

/// The original page's card, without its detail: the picture panel, the name, one line.
private struct SimpleGroupCard: View {
    let group: ExploreGroup
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ShowcasePicture(id: group.id.picture, scale: 1.15)
                .frame(height: 170).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.id.title).font(.system(.title3, design: .rounded, weight: .semibold))
                    Text(group.id.line).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                if group.isNew {
                    Text("New")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.sage))
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
