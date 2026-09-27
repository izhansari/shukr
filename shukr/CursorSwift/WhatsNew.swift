//
//  WhatsNew.swift
//  shukr
//
//  "What's new" — what changed in each commit and how to try it, so the owner knows what to test
//  in the build they're holding (2026-09-27, notes #16). Tap the build line (bottom of the ☰ menu
//  and of Settings). Only in DEBUG and TestFlight builds, never App Store ones.
//
//  Source: shukr/WhatsNew.json (bundled), chronological. Every commit that changes something a
//  user can see or feel adds an entry in the same commit (CLAUDE.md, near the top). An entry
//  committed with its change can't know its own hash, so it says "next";
//  `scripts/whatsnew.py resolve` fills in the real hash before the following commit. In a build,
//  "next" entries are therefore always part of that build.
//

import SwiftUI
import StoreKit

struct WhatsNewEntry: Decodable, Identifiable {
    let date: String          // "2026-09-27"
    let commit: String        // short hash, or "next"
    let title: String
    let tryIt: [String]
    let area: String
    let checked: String       // "sim" | "phone" | "no"
    var id: String { "\(commit)|\(title)" }

    /// Part of the build that's running.
    var inThisBuild: Bool { commit == "next" || commit == BuildInfo.commit }
}

enum WhatsNew {
    static let entries: [WhatsNewEntry] = {
        guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WhatsNewEntry].self, from: data) else { return [] }
        return list
    }()

    // MARK: NEW since the build you opened before this one

    private static let currentKey = "whatsNew.currentBuild"      // "<commit>|<yyyy-MM-dd>"
    private static let previousKey = "whatsNew.previousBuild"

    /// This build's identity; the first launch of a new build moves the old one to "previous".
    private static let previousBuild: (commit: String, date: String)? = {
        let d = UserDefaults.standard
        let day = BuildInfo.builtAt.map { PrayerNotificationID.dayKey($0) } ?? ""
        let current = "\(BuildInfo.stamp ?? "dev")|\(day)|\(BuildInfo.builtAt?.timeIntervalSince1970 ?? 0)"
        if d.string(forKey: currentKey) != current {
            if let old = d.string(forKey: currentKey) { d.set(old, forKey: previousKey) }
            d.set(current, forKey: currentKey)
        }
        guard let prev = d.string(forKey: previousKey) else { return nil }
        let parts = prev.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let commit = parts[0].hasSuffix("+") ? String(parts[0].dropLast()) : parts[0]
        return (commit, parts[1])
    }()

    /// Call once at launch so a new build is noticed even before the page is opened.
    static func noteLaunch() { _ = previousBuild }

    /// Entries added after the build you last had open.
    static let newIDs: Set<String> = {
        guard let prev = previousBuild else {
            // First time: this build's own entries.
            return Set(entries.filter(\.inThisBuild).map(\.id))
        }
        if let last = entries.lastIndex(where: { $0.commit == prev.commit }) {
            return Set(entries[(last + 1)...].map(\.id))
        }
        return Set(entries.filter { $0.date > prev.date }.map(\.id))
    }()

    // MARK: Tested ticks

    static let testedKey = "whatsNew.tested"
    static func tested() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: testedKey) ?? []) }
    static func setTested(_ id: String, _ on: Bool) {
        var set = tested()
        if on { set.insert(id) } else { set.remove(id) }
        UserDefaults.standard.set(Array(set), forKey: testedKey)
    }
}

/// Whether this build may show the page: DEBUG always; otherwise only TestFlight (sandbox) builds.
@MainActor final class WhatsNewAccess: ObservableObject {
    static let shared = WhatsNewAccess()
    @Published private(set) var available: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private init() {
        #if !DEBUG
        Task { @MainActor in
            if case .verified(let transaction) = try? await AppTransaction.shared {
                available = transaction.environment != .production
            }
        }
        #endif
    }
}

/// The build line, tappable into "What's new" where it's allowed.
struct BuildLineButton: View {
    var action: () -> Void
    @ObservedObject private var access = WhatsNewAccess.shared
    var body: some View {
        if access.available {
            Button(action: action) {
                HStack(spacing: 4) {
                    Text(BuildInfo.line)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("What's new in this build")
        } else {
            Text(BuildInfo.line)
        }
    }
}

// MARK: - The page

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tested = WhatsNew.tested()
    @AppStorage("whatsNew.untestedOnly") private var untestedOnly = false

    private var shown: [WhatsNewEntry] {
        WhatsNew.entries.filter { !untestedOnly || !tested.contains($0.id) }
    }
    /// Newest first: days, then commits within a day (in the order they were made, reversed).
    private var days: [(date: String, commits: [(commit: String, entries: [WhatsNewEntry])])] {
        var result: [(date: String, commits: [(commit: String, entries: [WhatsNewEntry])])] = []
        for entry in shown.reversed() {
            if result.last?.date != entry.date { result.append((entry.date, [])) }
            if result[result.count - 1].commits.last?.commit != entry.commit {
                result[result.count - 1].commits.append((entry.commit, []))
            }
            let c = result[result.count - 1].commits.count - 1
            result[result.count - 1].commits[c].entries.append(entry)
        }
        return result
    }
    private var untestedCount: Int { WhatsNew.entries.filter { !tested.contains($0.id) }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if shown.isEmpty {
                        Text(untestedOnly ? "Everything's ticked. Nice." : "Nothing here yet.")
                            .font(.subheadline).fontWeight(.light).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(days, id: \.date) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(dayLabel(day.date))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .tracking(1.4).textCase(.uppercase)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 4)
                            ForEach(day.commits, id: \.commit) { group in
                                commitCard(group.commit, group.entries)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground))
            .fontDesign(.rounded)
            .navigationTitle("What's new")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BuildInfo.line)
                .font(.footnote).foregroundStyle(.secondary)
            HStack {
                Text("\(untestedCount) untested")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button {
                    withAnimation(.snappy) { untestedOnly.toggle() }
                } label: {
                    Label("Untested only", systemImage: untestedOnly ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline)
                        .foregroundStyle(untestedOnly ? Color.green : Color.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(untestedOnly ? Color.green.opacity(0.12) : Color(.tertiarySystemFill)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func commitCard(_ commit: String, _ entries: [WhatsNewEntry]) -> some View {
        let thisBuild = entries.first?.inThisBuild ?? false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // "next": committed with this build (clean stamp), or not committed yet ("+").
                Text(commit != "next" ? commit
                     : (BuildInfo.stamp?.hasSuffix("+") ?? true) ? "not committed yet" : (BuildInfo.commit ?? "next"))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                if thisBuild {
                    Text("← this build")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                if i > 0 { Divider().padding(.leading, 14) }
                row(entry)
            }
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(thisBuild ? Color.green.opacity(0.35) : .clear, lineWidth: 1))
    }

    private func row(_ entry: WhatsNewEntry) -> some View {
        let done = tested.contains(entry.id)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.area)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .tracking(1).textCase(.uppercase)
                        .foregroundStyle(Color.sage)
                    if WhatsNew.newIDs.contains(entry.id) {
                        Text("NEW")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.green))
                    }
                    Text(checkedLabel(entry.checked))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(done ? .secondary : .primary)
                ForEach(Array(entry.tryIt.enumerated()), id: \.offset) { n, step in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n + 1).").monospacedDigit().foregroundStyle(.tertiary)
                        Text(step).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
            Spacer(minLength: 4)
            Button {
                let now = !done
                WhatsNew.setTested(entry.id, now)
                withAnimation(.snappy) {
                    if now { tested.insert(entry.id) } else { tested.remove(entry.id) }
                }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? Color.green : Color(.tertiaryLabel))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: done)
            .accessibilityLabel(done ? "Tested" : "Mark tested")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func checkedLabel(_ c: String) -> String {
        switch c {
        case "sim": "sim ✓"
        case "phone": "phone ✓"
        default: "not checked yet"
        }
    }

    private func dayLabel(_ key: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: key) else { return key }
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
