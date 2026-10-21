//
//  GoalLastWeek.swift
//  shukr
//
//  Your goal's "At this goal, last week" (owner, 2026-10-21, pick B; spec board/mocks/your-goal-v2/spec.md §4–5): the last
//  finished week counted at the step being tried — "was strong" / "wasn't strong", then only the reasons that matter ("only
//  show them reasoning for why strong if strong. and why not strong if not strong"), and excused days as a frosted chip that
//  opens "How excused plays towards goal:". No link off the page ("dont wanna send the user down a rabit hole. just say 7
//  missed"). Every number is the week's own (PrayerMetrics.Week): nothing here decides a week.
//

import SwiftUI

extension PrayerMetrics.Week {
    /// Missed, as the rule counts it: every unmarked prayer, and all five of a day with no record (excused ones never).
    var missed: Int { notMarked + 5 * noRecordDays }

    /// The excused prayers in a few words: "Tuesday" (a whole day), "Fajr on Monday" (one prayer), "2 days", "3 prayers";
    /// nil when none. `plural` says whether "was" or "were" follows.
    var excusedWords: (words: String, plural: Bool)? {
        let marked = days.map { d in (d, (0..<5).filter { d.states?[$0] == .excused }) }.filter { !$0.1.isEmpty }
        guard !marked.isEmpty else { return nil }
        let wholeDays = marked.allSatisfy { $0.1.count == 5 }
        let weekday = { (d: PrayerMetrics.Day) in d.date.formatted(.dateTime.weekday(.wide)) }
        if wholeDays {
            return marked.count == 1 ? (weekday(marked[0].0), false) : ("\(marked.count) days", true)
        }
        let n = marked.reduce(0) { $0 + $1.1.count }
        if n == 1, let (d, i) = marked.first, let k = i.first { return ("\(JourneyLog.names[k]) on \(weekday(d))", false) }
        return ("\(n) prayers", true)
    }
}

/// Excused Mode's frost (the chip, the sheet's icons): pale blue-grey, quiet, never a warning.
enum GoalFrost {
    static let fill = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.30, green: 0.35, blue: 0.43, alpha: 1) : UIColor(red: 0.875, green: 0.906, blue: 0.941, alpha: 1) })
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.74, green: 0.79, blue: 0.86, alpha: 1) : UIColor(red: 0.333, green: 0.396, blue: 0.478, alpha: 1) })
}

/// The slot between the steps and the button: always the same height for the usual states, so nothing moves as you try
/// steps (it grows only when larger text wraps the chips).
struct GoalLastWeek: View {
    let week: PrayerMetrics.Week?
    /// The weeks are counted (GoalPreview): until then the slot is empty, not "no week yet".
    let ready: Bool
    let goal: PrayerGoal
    let openExcused: () -> Void

    private var green: Color { GoalHero.colors[0] }

    var body: some View {
        VStack(spacing: 6) {
            Text("At this goal, last week")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .textCase(.uppercase).tracking(0.88)
                .foregroundStyle(.secondary)
            // The verdict and chips swap out, then in — only when what they say changes (steps that read the same don't blink).
            OutThenIn(value: Summary(week)) { detail($0) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .top)
        .opacity(ready ? 1 : 0)
        .animation(.easeOut(duration: 0.25), value: ready)
    }

    /// What the slot says for a week at the step tried — the rule's own numbers (Week.onTrack), only the ones that matter.
    private struct Summary: Equatable {
        enum Kind: Equatable { case noWeek, excused, judged }
        var kind = Kind.noWeek
        var strong = false
        /// Shown when the week was strong, or when it's what broke it.
        var missed: Int?
        /// Strong: always, but on Prayed (every prayed one meets it). Not strong: only past the 3 allowed.
        var later: Int?
        var excused: String?

        init(_ w: PrayerMetrics.Week?) {
            guard let w else { return }
            guard w.asked > 0 else { kind = .excused; return }
            kind = .judged
            strong = w.strong
            if strong || w.missed > 0 { missed = w.missed }
            if w.goal != .prayed && (strong || w.belowStep > PrayerMetrics.strongWeekSlack) { later = w.belowStep }
            excused = w.excusedWords?.words
        }
    }

    @ViewBuilder private func detail(_ s: Summary) -> some View {
        VStack(spacing: 6) {
            switch s.kind {
            case .noWeek:
                Text("After your first full week, you\u{2019}ll see how each step would have counted for you.")
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            case .excused:
                verdict("was excused", GoalFrost.ink)
                Text("Nothing was asked of you.")
                    .font(.system(size: 14, weight: .light, design: .rounded)).foregroundStyle(.secondary)
            case .judged:
                verdict(s.strong ? "was strong" : "wasn\u{2019}t strong", s.strong ? green : .primary)
                VStack(spacing: 6) {
                    ChipFlow(spacing: 6) { reasons(s) }
                    if let words = s.excused {
                        Button(action: openExcused) {
                            chip { Text("\(words) excused ") + Text("›").font(.system(size: 12, weight: .regular)) }
                                .foregroundStyle(GoalFrost.ink)
                                .background(Capsule().fill(GoalFrost.fill))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("How excused plays towards your goal")
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func verdict(_ words: String, _ color: Color) -> some View {
        Text(words)
            .font(.system(size: 24, weight: .light, design: .rounded))
            .foregroundStyle(color)
    }

    /// Not strong: what broke it, ink-outlined. Strong: the rules it kept, green with a ✓.
    @ViewBuilder private func reasons(_ s: Summary) -> some View {
        let allowed = " later than goal · \(PrayerMetrics.strongWeekSlack) allowed"
        if let n = s.missed {
            let words = (n == 0 ? Text("None").bold() : Text("\(n)").bold()) + Text(" missed")
            if s.strong { passed(words) } else { failed(words) }
        }
        if let n = s.later {
            let words = (n == 0 ? Text("None").bold() : Text("\(n)").bold()) + Text(allowed)
            if s.strong { passed(words) } else { failed(words) }
        }
    }

    private func chip(_ text: () -> Text) -> some View {
        text()
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
    }
    private func passed(_ text: Text) -> some View {
        chip { Text("✓ ") + text }
            .foregroundStyle(green)
            .background(Capsule().fill(green.opacity(0.14)))
    }
    private func failed(_ text: Text) -> some View {
        chip { text }
            .foregroundStyle(.primary)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.8), lineWidth: 1))
    }
}

/// "How excused plays towards goal:" — a small sheet, its height measured to what it holds (spec-pics 0, 6).
struct GoalExcusedSheet: View {
    let week: PrayerMetrics.Week
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 340

    var body: some View {
        let ex = week.excusedWords
        VStack(alignment: .leading, spacing: 18) {
            Text("How excused plays towards goal:")
                .font(.system(size: 22, weight: .light, design: .rounded))
                .padding(.bottom, 2)
            row(Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)),
                "Excused prayers aren\u{2019}t asked of you, so they\u{2019}re never missed.")
            row(Image(systemName: "smallcircle.filled.circle").font(.system(size: 11, weight: .regular)),
                "Your goal doesn\u{2019}t change: don\u{2019}t miss a prayer, and keep nearly all at your goal.")
            if let ex {
                row(Text("\(week.asked)").font(.system(size: 10.5, weight: .bold, design: .rounded)).monospacedDigit(),
                    "Last week \(ex.words) \(ex.plural ? "were" : "was") excused, so the week asked \(week.asked) prayers instead of \(week.days.count * 5).")
            }
            Button { dismiss() } label: {
                Text("Got it")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Capsule().fill(scheme == .dark ? Color.white : Color.black))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func row(_ icon: some View, _ words: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon.foregroundStyle(GoalFrost.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(GoalFrost.fill))
            Text(words)
                .font(.system(size: 15, weight: .light, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A swap that never overlaps: the old words fade out, then the new ones fade in (the app's "out, then in"; a crossfade
/// laid "Middle" over "Prayed" as you tapped across the steps). A fast run of changes lands on the last.
struct OutThenIn<Value: Equatable, Content: View>: View {
    let value: Value
    @ViewBuilder let content: (Value) -> Content
    @State private var shown: Value?
    @State private var latest: Value?
    @State private var on = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(shown ?? value)
            .opacity(on)
            .onChange(of: value) { _, new in
                latest = new
                withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.12)) { on = 0 } completion: {
                    shown = latest
                    withAnimation(.easeOut(duration: 0.2)) { on = 1 }
                }
            }
    }
}

/// Chips in centred rows, wrapping when they don't fit (larger text).
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.midX - row.width / 2
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(_ subviews: Subviews, width: CGFloat) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var out: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if let last = out.last, last.width + spacing + s.width <= width {
                out[out.count - 1] = (last.items + [i], last.width + spacing + s.width, max(last.height, s.height))
            } else {
                out.append(([i], s.width, s.height))
            }
        }
        return out
    }
}
