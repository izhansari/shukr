//
//  SessionResults.swift
//  shukr
//
//  A finished session's face in the ring (SessionDoneFace) and the count · time · rate tiles (ZikrBento) the pause
//  screen, the results and a zikr's page share. Moved out of tasbeehView.swift (cleanup-map tangle 5, step 3).
//

import SwiftUI
import SwiftData

/// The finished session in the soft look's centred ring, as the Zikr wheel will show it (decision session-flow-build A,
/// owner: "content inside of the circle could instead be the title of the task"): the task's title and, part-done,
/// where it stands; a free session's zikr with ⌄ (the picker moves the saved session). Above the ring, "Saved to your
/// history" and, after the session that kept it, the streak.
struct SessionDoneFace: View {
    @Environment(\.modelContext) private var context
    @Environment(SharedStateClass.self) var sharedState
    let session: SessionDataModel

    @State private var showMantraPicker = false
    @State private var chosenMantraName: String? = ""
    @State private var chosenMantraObject: MantraModel? = nil

    private var isTasbihFatimah: Bool { (session.mantra?.name ?? session.title) == PostSalahTasbeeh.mantraName }
    private var locked: Bool { session.task != nil || isTasbihFatimah }

    /// Today's progress on the session's task, this session included.
    private var taskProgress: TaskProgress? {
        guard let task = session.task else { return nil }
        let mine = task.sessions.filter { $0.startTime >= PrayerDay.sessionDayStart() }
        return TaskProgress(count: mine.reduce(0) { $0 + $1.totalCount },
                            seconds: mine.reduce(0) { $0 + $1.secondsPassed })
    }

    /// The streak, only after the session that finished the task's goal for today (as the results' hero).
    private var finishedStreak: TaskStreak? {
        guard let task = session.task, let p = taskProgress, task.isCompleted(with: p),
              session.startTime >= PrayerDay.sessionDayStart() else { return nil }
        let before = TaskProgress(count: p.count - session.totalCount, seconds: p.seconds - session.secondsPassed)
        guard !task.isCompleted(with: before) else { return nil }
        let streak = task.streak()
        return streak.current > 0 ? streak : nil
    }

    /// The task's own name, else the zikr's; a free session with none picked ("Untitled") asks for one.
    private var title: String {
        if let task = session.task { return task.title }
        if let name = session.mantra?.name { return name }
        return session.title == "Untitled" ? "" : session.title
    }

    var body: some View {
        face
            .frame(width: 200, height: 200)
            // Above the ring, its bottom 22 pt over the ring's top: it moves with the ring.
            .overlay(alignment: .top) {
                header
                    .fixedSize()
                    .alignmentGuide(.top) { $0[.bottom] + 22 }
            }
            .onChange(of: chosenMantraName) {
                guard let newName = chosenMantraName, !newName.isEmpty else { return }
                withAnimation {
                    sharedState.titleForSession = newName
                    sharedState.mantraForSession = chosenMantraObject
                    session.title = newName   // the saved session moves to that zikr
                    // The tips' practice session lives in a store of its own: its name only, never a link to a row here.
                    guard !CountTips.shared.isPractice(session.id) else { return }
                    session.mantra = chosenMantraObject
                    do { try context.save() } catch { print("Error saving context: \(error)") }
                }
            }
            .sheet(isPresented: $showMantraPicker) {
                MantraPickerView(
                    isPresented: $showMantraPicker,
                    selectedMantra: $chosenMantraName,
                    selectedMantraObject: $chosenMantraObject,
                    presentation: [.large]
                )
            }
    }

    /// The wheel's face (ZikrCircleFace): the title, the zikr under a task's own name, then where it stands.
    private var face: some View {
        VStack(spacing: 4) {
            Button { showMantraPicker = true } label: {
                HStack(spacing: 6) {
                    Text(title.isEmpty ? "choose a zikr" : title)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .foregroundStyle(title.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                    if !locked {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: 150)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!locked)
            if let task = session.task, let line = task.mantraLine {
                Text(line)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 150)
                    .padding(.top, -3)
            }
            subtitle
                .font(.subheadline)
                .fontWeight(.thin)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 150)
        }
        .fontDesign(.rounded)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // inside the ring: the largest sizes ran out of it (Sami's B3)
    }

    @ViewBuilder private var subtitle: some View {
        if let task = session.task, let p = taskProgress {
            // Done: nothing more in the ring — "Saved to your history" and the streak above it say it (owner crossed out
            // "✓ done today", decision stats-weight).
            if !task.isCompleted(with: p) {
                Text(task.isCountMode ? "\(p.count) of \(task.goal)" : "\(Int(p.seconds / 60)) of \(task.goal) min")
                    .foregroundStyle(.secondary)
            }
        } else if isTasbihFatimah {
            Text("33 · 33 · 34 after salah").foregroundStyle(.secondary)
        } else {
            Text(session.sessionMode == 1 ? "\(session.targetMin) min session"
                 : session.sessionMode == 2 ? "\(session.targetCount) count session" : "freestyle")
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                Text("Saved to your history")
                    .font(.system(size: 19, weight: .light, design: .rounded))
            }
            .foregroundStyle(Color.sage)
            if let streak = finishedStreak {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.sage)
                    Text(streak.current >= streak.best ? "Day \(streak.current) · your best yet"
                                                       : "Day \(streak.current) · your best is \(streak.best)")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .regular, design: .rounded))
            }
        }
    }
}

/// Count, time and rate as glass tiles (same material and light rounded type as the pause
/// screen's mantra card), shared by the pause and results screens. Count and time stacked on
/// the left, rate on the right — tap it to flip per count ↔ per tasbeeh. With `finish` (a count goal in progress) a full-width tile underneath says when
/// you'll be done — "in 1m 20s", tap → "6:42 PM" — a tile so it reads as something to tap
/// (owner, 2026-09-25; it used to be loose caption text under the boxes).
struct ZikrBento: View {
    let count: Int
    let seconds: TimeInterval
    let secondsPerCount: Double
    let perTasbeeh: String
    /// Seconds left to the goal; the finish time is now + this, kept current by the minute (a paused session's
    /// finish moves on with the clock).
    var finishIn: TimeInterval? = nil
    /// Lifetime use (a mantra's page): "25m 56s" instead of a stopwatch, other captions, and
    /// flat grouped-list tiles instead of glass.
    var timeText: String? = nil
    var countCaption = "count"
    var timeCaption = "time"
    var grouped = false
    /// Your usual pace for this zikr (`MantraModel.secondsPerCount`, this session left out): the
    /// rate tile says how this session compares — faster in sage, slower in secondary, never red.
    /// Nil = no line (first session, freestyle with no zikr, a mantra's lifetime page).
    var usualSecondsPerCount: Double? = nil

    @State private var showingPerCount = true
    @State private var showingFinishTime = false

    private let gap: CGFloat = 10
    private let tileHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: gap) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    // Count and time just show (the old spin-and-buzz on tap did nothing — owner).
                    tile {
                        row(icon: "circle.hexagonpath", value: count.formatted(), caption: countCaption)
                    }
                    tile {
                        row(icon: "gauge.with.needle", value: timeText ?? timerStyle(seconds), caption: timeCaption)
                    }
                }

                tile {
                    VStack(spacing: 4) {
                        Text("rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        flip(showingPerCount,
                             String(format: "%.2fs", secondsPerCount), "per count",
                             perTasbeeh, "per tasbeeh", size: 30)
                        if let line = paceComparison(perCount: true), let line2 = paceComparison(perCount: false) {
                            ZStack {
                                comparisonText(line).opacity(showingPerCount ? 1 : 0)
                                comparisonText(line2).opacity(showingPerCount ? 0 : 1)
                            }
                            .padding(.top, 6)
                        }
                    }
                    // It flips: the same ⇆ as the finish tile (owner, 2026-09-28).
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) { flipMark.padding(12) }
                }
                .frame(height: tileHeight * 2 + gap)
                .onTapGesture {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingPerCount.toggle() }
                }
            }

            if let finishIn {
                tile {
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        ZStack(alignment: .leading) {
                            sentence(String(inMinSecStyle2(from: finishIn).dropFirst(3)), "left until you finish")
                                .opacity(showingFinishTime ? 0 : 1)
                                .offset(y: showingFinishTime ? -16 : 0)
                            TimelineView(.everyMinute) { now in
                                sentence(shortTime(now.date.addingTimeInterval(finishIn)), "is your estimated finish")
                            }
                                .opacity(showingFinishTime ? 1 : 0)
                                .offset(y: showingFinishTime ? 0 : 16)
                        }
                        Spacer(minLength: 0)
                        flipMark
                    }
                    .padding(.horizontal, 16)
                    .frame(height: tileHeight)
                }
                .onTapGesture {
                    triggerSomeVibration(type: .medium)
                    withAnimation(.easeInOut(duration: 0.3)) { showingFinishTime.toggle() }
                }
                .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // tiles keep their height outside a ScrollView
    }

    /// The mark on every tile that flips on a tap (finish, rate).
    private var flipMark: some View {
        Image(systemName: "arrow.left.arrow.right")
            .font(.caption.weight(.medium))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// This session against your usual pace, per count or per tasbeeh (100 counts, like the rate):
    /// "0.7s faster", "1m 10s slower", "about your usual" within 5 %. Nil without a usual pace.
    private func paceComparison(perCount: Bool) -> (text: String, faster: Bool?)? {
        Self.paceComparison(secondsPerCount: secondsPerCount, usual: usualSecondsPerCount, perCount: perCount)
    }

    /// The same line for the soft session's per-count tile (decision session-flow-build A).
    static func paceComparison(secondsPerCount: Double, usual: Double?, perCount: Bool) -> (text: String, faster: Bool?)? {
        guard let usual, usual > 0, secondsPerCount > 0 else { return nil }
        let diff = secondsPerCount - usual
        if abs(diff) / usual < 0.05 { return ("about your usual", nil) }
        let amount = abs(diff) * (perCount ? 1 : 100)
        let text: String
        if perCount {
            text = amount < 0.1 ? String(format: "%.2fs", amount) : String(format: "%.1fs", amount)
        } else {
            let whole = Int(amount.rounded())
            text = whole >= 60 ? "\(whole / 60)m \(whole % 60)s" : "\(whole)s"
        }
        return ("\(text) \(diff < 0 ? "faster" : "slower")", diff < 0)
    }

    private func comparisonText(_ line: (text: String, faster: Bool?)) -> some View {
        Text(line.text)
            .font(.system(size: 13, weight: line.faster == true ? .medium : .regular, design: .rounded))
            .foregroundStyle(line.faster == true ? Color.sage : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
    }

    /// "1m 37s left until you finish" as one line: the number first in the tiles' type, the
    /// words after it, quiet (owner, 2026-09-25).
    private func sentence(_ value: String, _ words: String) -> some View {
        (Text(value).font(.system(size: 22, weight: .light, design: .rounded))
            + Text(" " + words).font(.subheadline).foregroundColor(.secondary))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: tileHeight)
            .background {
                if grouped {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(grouped ? 0 : 0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(grouped ? 0 : 0.1), radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(icon: String, value: String, caption: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            valueStack(value, caption, size: 22, leading: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: tileHeight)
    }

    /// Two value / caption pairs in one place; the shown one slides up and out as the other
    /// slides in (the rate box's old flip).
    private func flip(_ showFirst: Bool, _ v1: String, _ c1: String, _ v2: String, _ c2: String,
                      size: CGFloat, leading: Bool = false) -> some View {
        ZStack(alignment: leading ? .leading : .center) {
            valueStack(v1, c1, size: size, leading: leading)
                .opacity(showFirst ? 1 : 0)
                .offset(y: showFirst ? 0 : -16)
            valueStack(v2, c2, size: size, leading: leading)
                .opacity(showFirst ? 0 : 1)
                .offset(y: showFirst ? 16 : 0)
        }
    }

    private func valueStack(_ value: String, _ caption: String, size: CGFloat, leading: Bool) -> some View {
        VStack(alignment: leading ? .leading : .center, spacing: leading ? 0 : 2) {
            Text(value)
                .font(.system(size: size, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, leading ? 0 : 10)
    }
}
