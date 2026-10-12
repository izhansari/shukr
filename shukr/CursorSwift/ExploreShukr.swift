//
//  ExploreShukr.swift
//  shukr
//
//  Settings → Explore shukr (owner, ask settings-explore: "a section in settings … where we can market or sell the other
//  features that we have that we don't really talk about, like the widgets, the lock screen widgets, shortcuts, app
//  intent"). A rough pass, to be made beautiful later: a card per feature people don't find — a box where its picture
//  will go, one line on why it's nice, and one action: Set it up where shukr can do it, "How to add it" where only iOS can.
//

import SwiftUI

struct ExploreShukrPage: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ExploreCard(symbol: "square.grid.2x2", title: "Home Screen widgets",
                            why: "Your prayer's ring on your Home Screen, and mark it prayed right there.",
                            steps: ["Touch and hold an empty spot on your Home Screen.",
                                    "Tap Edit, then Add Widget.",
                                    "Search for shukr and pick a size."])
                ExploreCard(symbol: "lock.rectangle.on.rectangle", title: "Lock Screen widgets",
                            why: "How long is left at a glance, every time you pick up your phone.",
                            steps: ["Touch and hold your Lock Screen, then tap Customize.",
                                    "Choose your Lock Screen and tap the widget area.",
                                    "Pick one of shukr's."])
                if PrayerLiveActivities.supported {
                    ExploreCard(symbol: "platter.filled.bottom.iphone", title: "Live Activities",
                                why: "The prayer counting down on your Lock Screen and in the Dynamic Island.",
                                action: ("Set it up", { jump(SettingsJump.liveActivities) }))
                }
                ExploreCard(symbol: "switch.2", title: "Control Center",
                            why: "Qibla and Tasbeeh one swipe away, even from another app.",
                            steps: ["Swipe down from the top-right corner of your screen.",
                                    "Tap + at the top left, then Add a Control.",
                                    "Search for shukr and pick Qibla or Tasbeeh."])
                ExploreCard(symbol: "waveform", title: "Siri and Shortcuts",
                            why: "Ask Siri “Next prayer time from shukr”, or use shukr in your own Shortcuts.",
                            action: ("Open Shortcuts", {
                                if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                            }))
                ExploreCard(symbol: "applewatch", title: "Apple Watch",
                            why: "Mark prayers, count zikr with the Crown and find the qibla from your wrist.",
                            steps: ["Open the Watch app on your iPhone.",
                                    "Scroll to Available Apps.",
                                    "Tap Install next to shukr."])
                ExploreCard(symbol: "alarm", title: "Fajr alarm",
                            why: "A real alarm that moves with Fajr every day, so there's nothing to set before bed.",
                            action: ("Set it up", { jump(SettingsJump.fajrAlarm) }))
                ExploreCard(symbol: "photo.stack", title: "Memories",
                            why: "A photo after you pray, kept day by day.",
                            action: ("Open Memories", { MemoriesPresenter.shared.open = true }))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Explore shukr")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }

    /// Back to Settings, then to that side of Reminders (SettingsJump).
    private func jump(_ target: String) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))   // the pop first, so the scroll lands
            SettingsJump.shared.request(target)
        }
    }
}

/// One feature: its picture's place, its name, why it's nice, and its one action.
private struct ExploreCard: View {
    let symbol: String
    let title: String
    let why: String
    var steps: [String]? = nil
    var action: (String, () -> Void)? = nil
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Where its picture goes (a rough pass: the symbol stands in).
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.sage.opacity(0.14))
                .frame(height: 120)
                .overlay(Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(Color.sage))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(.title3, design: .rounded, weight: .semibold))
                Text(why).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let steps {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { open.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("How to add it")
                        Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.sage)
                }
                .buttonStyle(.plain)
                if open {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)").font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.sage).frame(width: 16)
                                Text(step).font(.system(.subheadline, design: .rounded))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            if let action {
                Button {
                    triggerSomeVibration(type: .light)
                    action.1()
                } label: {
                    Text(action.0)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.sage)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
