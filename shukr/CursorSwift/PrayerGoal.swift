import SwiftUI

// The prayer goal (owner, 2026-10-18): "a setting where user can choose their goal. like for me my goal is to pray all perfect.
// some might be middle and perfect. some might be perfect middle and closing (in window). This is the real goal and the metric
// that matters most for people." It decides which days keep the streak and count as met (Journey's green days, its rate, the
// runs) — never a prayer's score or grade. Flipping it recounts history at the new bar (nothing stored: "i want it to be
// something the user can easily change and flip between"); the fresh start (FreshStart.swift) is where every count begins.
// The rule lives here only: PrayerViewModel.gradingCriteria, YourJourneyStats.streakDay and JourneyLog.Day all ask it.

/// Which prayers count toward the goal. Stored under the old hidden streak-mode key, whose values it keeps (1 = any mark,
/// 2 = in its window, 3 = Middle or better), so nobody's streak moves on update; Perfect is new.
enum PrayerGoal: Int, CaseIterable, Identifiable {
    case prayed = 1, inWindow = 2, onTime = 3, perfect = 4

    static let key = "prayerStreakMode"
    var id: Int { rawValue }

    static var current: PrayerGoal {
        PrayerGoal(rawValue: UserDefaults.standard.object(forKey: key) as? Int ?? 1) ?? .prayed
    }

    /// The lowest score that meets it; nil: any mark (a Qaza too).
    var floor: Double? {
        switch self {
        case .prayed: nil
        case .inWindow: PrayerScoring.inWindowFloor
        case .onTime: 0.8
        case .perfect: 1
        }
    }

    /// A prayed prayer's score meets it (PrayerScoring.grade's own edges).
    func meets(score: Double) -> Bool {
        switch self {
        case .prayed: true
        case .inWindow: score >= PrayerScoring.inWindowFloor - 0.0001
        case .onTime: score >= 0.8
        case .perfect: score >= 0.9999
        }
    }

    /// Settings' words, in the grades users see on every mark.
    var title: String {
        switch self {
        case .prayed: "Pray all five"
        case .inWindow: "In their windows"
        case .onTime: "On time"
        case .perfect: "Perfect"
        }
    }
    var line: String {
        switch self {
        case .prayed: "Every prayer counts, made up ones too."
        case .inWindow: "Perfect, Middle or Closing: before its time ends."
        case .onTime: "Perfect or Middle."
        case .perfect: "All five in their first 30 minutes."
        }
    }
    /// A day that met it, in a few words (the legend, the runs): "All five prayed", "All five Perfect" …
    var dayWords: String {
        switch self {
        case .prayed: "All five prayed"
        case .inWindow: "All five in time"
        case .onTime: "All five on time"
        case .perfect: "All five Perfect"
        }
    }

    /// A streak of days that met it, after "N days in a row, " (the milestones).
    var runWords: String {
        switch self {
        case .prayed: "all five prayed"
        case .inWindow: "all in time"
        case .onTime: "all on time"
        case .perfect: "all Perfect"
        }
    }
    /// After "all five prayers …" (a milestone's card).
    var prayersWords: String {
        switch self {
        case .prayed: "prayed"
        case .inWindow: "prayed in time"
        case .onTime: "prayed on time"
        case .perfect: "Perfect"
        }
    }

    /// Sets it and lets every count redo itself (no celebrations: PrayerStats.changed).
    @MainActor static func set(_ goal: PrayerGoal) {
        guard goal != current else { return }
        UserDefaults.standard.set(goal.rawValue, forKey: key)
        PrayerStats.changed()
    }
}

/// The two settings every count reads — the goal and the fresh start — and the one event when either changes.
enum PrayerStats {
    /// Posted after the goal or the fresh start changed: the Salah page recounts its streak silently, Journey and Prayer
    /// scores rebuild (their caches go). `.journeyChanged` follows, so the pages that already reload on it do.
    static let rulesChanged = Notification.Name("PrayerStats.rulesChanged")

    @MainActor static func changed() {
        NotificationCenter.default.post(name: rulesChanged, object: nil)
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
    }

    /// The first prayer day that counts: the fresh start's, or nil (all of them).
    static var countsFrom: Date? { FreshStart.start }

    /// A prayer day (its start) counts toward streaks, rates, ranks and runs.
    static func counts(_ dayStart: Date) -> Bool {
        guard let from = countsFrom else { return true }
        return dayStart >= from
    }
}

/// Settings' row (Journey section): the goal's name.
struct PrayerGoalSettingsRow: View {
    @State private var goal = PrayerGoal.current
    var body: some View {
        NavigationLink { PrayerGoalPage() } label: {
            HStack(spacing: 12) {
                Image(systemName: "target").frame(width: 24)
                Text("Your goal").lineLimit(1)
                Spacer(minLength: 8)
                Text(goal.title).foregroundStyle(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .onReceive(NotificationCenter.default.publisher(for: PrayerStats.rulesChanged)) { _ in goal = PrayerGoal.current }
        .onAppear { goal = PrayerGoal.current }
    }
}

/// The four goals, each with the streak it would give you now (from Journey's log, when it's been read) — a flip's cost
/// seen before it's made. Card look's list (a title, a grey line, the sage check).
struct PrayerGoalPage: View {
    @State private var goal = PrayerGoal.current
    /// Each goal's streak today (nil: Journey's log isn't read yet).
    @State private var streaks: [PrayerGoal: Int] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(PrayerGoal.allCases) { option in
                    Button {
                        guard option != goal else { return }
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.25)) { goal = option }
                        PrayerGoal.set(option)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).foregroundStyle(.primary)
                                Text(option.line).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if let n = streaks[option] {
                                Text(n == 1 ? "1 day" : "\(n) days").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Color.sage)
                                .opacity(option == goal ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(AppIconChoice.rowInsets)
                }
            } footer: {
                Text("Your streak, Journey's days and its rate follow your goal. Change it any time: they're counted again. Scores never change.")
            }
        }
        .navigationTitle("Your goal")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let log = JourneyLog.last else { return }
            let today = PrayerDay.start()
            let excused = Excused.Days(Excused.ranges)
            var all: [PrayerGoal: Int] = [:]
            for g in PrayerGoal.allCases { all[g] = YourJourneyStats.currentStreak(log: log, goal: g, today: today, excused: excused) }
            streaks = all
        }
    }
}
