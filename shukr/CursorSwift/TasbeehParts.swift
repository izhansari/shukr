//
//  TasbeehParts.swift
//  shukr
//
//  The session's results screen and its three bar buttons (⏸ / − / the top button), nested in `tasbeehView` as before —
//  an extension, so their names and code are unchanged. Moved out of tasbeehView.swift (cleanup-map tangle 5, step 2).
//

import SwiftUI
import SwiftData

extension tasbeehView {
    // MARK: - Helper Structs (basically moved from Utils)
    
    /// After Finish (restyled 2026-09-25 to match the pause screen): a sage check that pops in,
    /// "saved to your history", the mantra card (tap to put the session on another mantra —
    /// not for a task's session, which stays on its task's mantra), the shared bento, and Done.
    struct ResultsView: View {
        @Environment(\.modelContext) private var context
        @Environment(SharedStateClass.self) var sharedState
        @Binding var isPresented: Bool
        let savedSession: SessionDataModel
        /// Only after a sleep finish: carry the same session on (he was only dozing).
        var keepCounting: (() -> Void)? = nil
        /// Saved by sleep mode: no buzz from the streak moment.
        var asleep = false

        @State private var showMantraPicker = false
        @State private var chosenMantraName: String? = ""
        @State private var chosenMantraObject: MantraModel? = nil
        @State private var checkShown = false
        @State private var showHistory = false

        private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
        private var isTasbihFatimah: Bool {
            (savedSession.mantra?.name ?? savedSession.title) == PostSalahTasbeeh.mantraName
        }
        /// A task's session keeps its task's mantra; Tasbih Fatimah is always Tasbih Fatimah.
        private var locked: Bool {
            savedSession.task != nil || (savedSession.mantra?.name ?? savedSession.title) == PostSalahTasbeeh.mantraName
        }
        private var title: String { savedSession.mantra?.name ?? savedSession.title }

        /// A task's session: where the task stands today ("5 of 100 today"), since a continued
        /// session saves only its own counts.
        /// Today's progress on the session's task, this session included (nil: not a task session).
        private var taskProgress: TaskProgress? {
            guard let task = savedSession.task else { return nil }
            let mine = task.sessions.filter { $0.startTime >= PrayerDay.sessionDayStart() }
            return TaskProgress(count: mine.reduce(0) { $0 + $1.totalCount },
                                seconds: mine.reduce(0) { $0 + $1.secondsPassed })
        }

        /// The streak moment: only after the session that finished the task's goal for today (it wasn't
        /// done without this session's counts).
        private var finishedStreak: TaskStreak? {
            guard let task = savedSession.task, let p = taskProgress, task.isCompleted(with: p),
                  savedSession.startTime >= PrayerDay.sessionDayStart() else { return nil }
            let before = TaskProgress(count: p.count - savedSession.totalCount, seconds: p.seconds - savedSession.secondsPassed)
            guard !task.isCompleted(with: before) else { return nil }
            let streak = task.streak()
            return streak.current > 0 ? streak : nil
        }

        /// The card's line for a task session: where the task stands, never this session's count again
        /// (the tile has it; owner: "it says 50 three times"). "Done for today" / "70 to go today", with
        /// the streak still to keep after it.
        private func taskLine(_ task: TaskModel, _ p: TaskProgress) -> Text {
            let prefix = task.mantraLine == nil ? Text("") : Text("\(task.title) · ")
            if task.isCompleted(with: p) {
                return prefix.foregroundStyle(.secondary) + Text("Done for today").foregroundStyle(Color.sage)
            }
            let left = task.isCountMode ? "\(task.goal - p.count) to go today"
                                        : "\(max(1, Int((Double(task.goal * 60) - p.seconds) / 60 + 0.5))) min to go today"
            var line = prefix + Text(left)
            let streak = task.streak()
            if streak.current > 0 {
                line = line + Text(" · ") + Text(Image(systemName: "flame")) + Text(" keeps your \(streak.current)")
            }
            return line.foregroundStyle(.secondary)
        }

        private var sessionLabel: String {
            switch savedSession.sessionMode {
            case 1: return "\(savedSession.targetMin) min session"
            case 2: return "\(savedSession.targetCount) count session"
            default: return "freestyle session"
            }
        }

        var body: some View {
            ZStack {
                Color("pauseColor")
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    Spacer(minLength: 20)
                    Group {
                        if let streak = finishedStreak {
                            StreakResultsHero(streak: streak, quiet: asleep)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(Color.sage)
                                    .frame(width: 52, height: 52)
                                    .background(Circle().fill(Color.sage.opacity(0.16)))
                                    .scaleEffect(checkShown ? 1 : 0.4)
                                    .opacity(checkShown ? 1 : 0)
                                Text("saved to your history")
                                    .font(.system(size: 17, weight: .light, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 22)

                    VStack(spacing: 12) {
                        mantraCard
                        ZikrBento(count: savedSession.totalCount, seconds: savedSession.secondsPassed,
                                  secondsPerCount: savedSession.avgTimePerClick,
                                  perTasbeeh: savedSession.tasbeehRate,
                                  usualSecondsPerCount: savedSession.mantra?.secondsPerCount(excluding: savedSession))
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 20)

                    if let keepCounting {
                        Button(action: keepCounting) {
                            Label("Keep counting", systemImage: "play.fill")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(Color.sage)
                                .background(Capsule().fill(Color.sage.opacity(0.06)))
                                .overlay(Capsule().stroke(Color.sage.opacity(0.6), lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                        .transition(.opacity)
                    }

                    Button {
                        triggerSomeVibration(type: .success)
                        // Cleared once the session has gone: under a soft close the results are still fading (their
                        // title would read "Untitled" mid-fade).
                        SessionHandoff.shared.afterClose {
                            sharedState.titleForSession = ""
                            sharedState.mantraForSession = nil   // audit A8: a stale pick outlived a deleted zikr
                        }
                        CountTips.shared.resultsDone()
                        isPresented = false
                    } label: {
                        Text("Done")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(Color.sage)
                            .background(Capsule().fill(Color.sage.opacity(0.18)))
                            .contentShape(Capsule())
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.done", $0) }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)

                    Button {
                        triggerSomeVibration(type: .light)
                        showHistory = true
                    } label: {
                        Label("View zikr history", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    // History is the Zikr tab's: shut while it's locked (a session from the post-salah pill — ZikrLock).
                    .opacity(ZikrLock.shared.locked ? 0 : 1)
                    .disabled(ZikrLock.shared.locked)
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                }
                .fontDesign(.rounded)
            }
            .task {
                // A beat after the card, then the ✓'s spring: the wait is a pause, never `.delay` on a spring.
                guard await CircleGate.pause(CircleMotion.resultsCheckBeat) else { return }
                withAnimation(CircleMotion.resultsCheck) { checkShown = true }
            }
            .onChange(of: chosenMantraName) {
                guard let newName = chosenMantraName, !newName.isEmpty else { return }
                withAnimation {
                    sharedState.titleForSession = newName
                    sharedState.mantraForSession = chosenMantraObject
                    savedSession.title = newName   // the saved session moves to that mantra
                    // The tips' practice session lives in a store of its own: its name only, never a link to a row here.
                    guard !CountTips.shared.isPractice(savedSession.id) else { return }
                    savedSession.mantra = chosenMantraObject
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
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    HistoryPageView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showHistory = false }
                            }
                        }
                }
            }
        }

        private var mantraCard: some View {
            Button { showMantraPicker = true } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title.isEmpty ? "choose a zikr" : title)
                                .font(.system(size: 24, weight: .light, design: .rounded))
                                .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                            if !locked {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Group {
                            if let task = savedSession.task, let p = taskProgress {
                                taskLine(task, p)
                            } else {
                                Text(isTasbihFatimah ? "33 · 33 · 34 after salah" : sessionLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(cardShape.fill(.ultraThinMaterial))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .contentShape(cardShape)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!locked)   // not .disabled: that grayed the card out
        }
    }

    #Preview {
        ResultsView(
            isPresented: .constant(true),
            savedSession: SessionDataModel(
                title: "yo",
                sessionMode: 1,
                targetMin: 1,
                targetCount: 5,
                totalCount: 66,
                startTime: Date(),
                secondsPassed: 72,
                avgTimePerClick: 0.54,
                tasbeehRate: "10m 4s"
            )
        )
        .environment(SharedStateClass())
    }

    struct TopOfSessionButton: View{
        var symbol: String? = nil   // an SF Symbol…
        var text: String? = nil     // …or a short label like "+10"
        let actionToDo: () -> Void
        let paused: Bool
        let togglePause: () -> Void
        /// A switched-on toggle (count in sets): green label on a green tint with a green edge.
        var active = false

        init(symbol: String, actionToDo: @escaping () -> Void, paused: Bool, togglePause: @escaping () -> Void) {
            self.symbol = symbol; self.actionToDo = actionToDo; self.paused = paused; self.togglePause = togglePause
        }
        init(text: String, actionToDo: @escaping () -> Void, paused: Bool, togglePause: @escaping () -> Void, active: Bool = false) {
            self.text = text; self.actionToDo = actionToDo; self.paused = paused; self.togglePause = togglePause
            self.active = active
        }
        
        var body: some View{
            Button(action: paused ? togglePause : actionToDo) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 20, height: 20)
                    } else {
                        Text(text ?? "")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(minWidth: 20, minHeight: 20)
                    }
                }
                    .foregroundColor(active ? .green : .gray.opacity(0.3))
                    .padding()
                    .background(paused ? .clear : (active ? Color.green.opacity(0.14) : .gray.opacity(0.08)))
                    .cornerRadius(100)
                    .overlay(Capsule().strokeBorder(Color.green.opacity(active && !paused ? 0.6 : 0), lineWidth: 1))
                    .opacity(paused ? 0 : 1.0)
            }
        }
    }
    
    
    /// − while counting; paused, the same button becomes Finish (decision minus-finish-morph, owner: "make the transition for
    /// the minus button to turn into the finish button"), as ⏸ becomes ‹ Resume: one view the whole time, so the circle
    /// stretches into the capsule while − shrinks and fades and "Finish" grows in, the grey fill crossfading to the raised
    /// capsule. Its first tap paused arms it: "✓ Tap again to finish" grows leftwards over the session's line. Always
    /// 56 pt tall, as the bar.
    struct MinusFinishButton: View {
        let paused: Bool
        let armed: Bool
        /// The soft look's raised capsule; else a plain tint.
        var raised = false
        var reduceMotion = false
        let action: () -> Void

        static let minusSize: CGFloat = 52
        static let finishHeight: CGFloat = 40
        static let finishPadding: CGFloat = 18
        /// "Finish"'s own width at its font, measured.
        static let finishTextWidth: CGFloat = {
            let base = UIFont.systemFont(ofSize: 17, weight: .medium)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 17) } ?? base
            return ceil(("Finish" as NSString).size(withAttributes: [.font: font]).width)
        }()

        var body: some View {
            Button(action: action) {
                ZStack {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.gray.opacity(0.3))
                        .opacity(paused ? 0 : 1)
                        .scaleEffect(paused ? 0.6 : 1)
                    Text("Finish")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .fixedSize()
                        .opacity(paused && !armed ? 1 : 0)
                        .scaleEffect(paused ? 1 : 0.6)
                }
                .frame(width: paused ? Self.finishTextWidth + 2 * Self.finishPadding : Self.minusSize,
                       height: paused ? Self.finishHeight : Self.minusSize)
                .background {
                    ZStack {
                        Capsule().fill(Color.gray.opacity(0.08))
                            .opacity(paused ? 0 : 1)
                        Group {
                            if raised {
                                ThemedRaised(shape: Capsule(), radius: 4, offset: 2)
                            } else {
                                Capsule().fill(Color.primary.opacity(0.06))
                            }
                        }
                        .opacity(paused && !armed ? 1 : 0)
                    }
                }
                // Armed: its words grow leftwards over the session's line (an overlay: no width while hidden).
                .overlay(alignment: .trailing) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                        Text("Tap again to finish").font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: Self.finishHeight)
                    .background(Capsule().fill(Color.sage))
                    .fixedSize()
                    .opacity(paused && armed ? 1 : 0)
                    .scaleEffect(armed ? 1 : 0.9, anchor: .trailing)
                    .animation(.snappy(duration: 0.25), value: armed)
                }
                .frame(height: PauseResumeButton.barHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(CircleMotion.movement(CircleMotion.pauseMorph, reduced: reduceMotion), value: paused)
            .accessibilityLabel(!paused ? "Minus one" : armed ? "Tap again to finish" : "Finish")
        }

        /// The paused capsule's layout alone (no fill): the pause screen keeps its room with it, unseen.
        static var finishLabel: some View {
            Text("Finish")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .fixedSize()
                .padding(.horizontal, finishPadding)
                .frame(height: finishHeight)
        }
    }

    /// ⏸ while counting; paused, the same button becomes ‹ Resume (decision pause-resume-morph A, owner: "ideally they
    /// are the same button"). One view the whole time — never removed, never swapped — so SwiftUI interpolates it: the
    /// grey square widens into the sage capsule, its corners round, the symbol changes in place (symbol replace) and
    /// "Resume" fades in beside it; resuming plays it backwards, and a tap mid-way just turns it round. One named timing
    /// (CircleMotion.pauseMorph), a plain fade under Reduce Motion. Always 56 pt tall, so the bar never changes height
    /// (the pause screen's top row matches the bar).
    struct PauseResumeButton: View {
        let paused: Bool
        /// The soft look's raised capsule; else a plain tint — as Finish (owner: "make resume button match the finished
        /// button … just put green … text on it. otherwise match it and its animation exactly").
        var raised = false
        var reduceMotion = false
        let action: () -> Void

        /// Paused: the capsule's sizes (Finish's), shared with the pause screen's unseen twin (`resumeLabel`).
        static let resumeHeight: CGFloat = MinusFinishButton.finishHeight
        static let resumePadding: CGFloat = MinusFinishButton.finishPadding
        static let barHeight: CGFloat = 56
        static let pauseSize: CGFloat = MinusFinishButton.minusSize
        /// "Resume"'s own width at its font, measured.
        static let resumeTextWidth: CGFloat = {
            let base = UIFont.systemFont(ofSize: 17, weight: .medium)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 17) } ?? base
            return ceil(("Resume" as NSString).size(withAttributes: [.font: font]).width)
        }()

        var body: some View {
            // Finish's morph, mirrored: ⏸ in its grey square shrinks away as the square widens into the capsule and
            // "Resume" grows in; resuming plays it backwards.
            Button(action: action) {
                ZStack {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.gray.opacity(0.3))
                        .opacity(paused ? 0 : 1)
                        .scaleEffect(paused ? 0.6 : 1)
                    Text("Resume")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.sage)
                        .fixedSize()
                        .opacity(paused ? 1 : 0)
                        .scaleEffect(paused ? 1 : 0.6)
                }
                .frame(width: paused ? Self.resumeTextWidth + 2 * Self.resumePadding : Self.pauseSize,
                       height: paused ? Self.resumeHeight : Self.pauseSize)
                .background {
                    ZStack {
                        Capsule().fill(Color.gray.opacity(0.08))
                            .opacity(paused ? 0 : 1)
                        Group {
                            if raised {
                                ThemedRaised(shape: Capsule(), radius: 4, offset: 2)
                            } else {
                                Capsule().fill(Color.primary.opacity(0.06))
                            }
                        }
                        .opacity(paused ? 1 : 0)
                    }
                }
                .frame(height: Self.barHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(CircleMotion.movement(CircleMotion.pauseMorph, reduced: reduceMotion), value: paused)
            .accessibilityLabel(paused ? "Resume" : "Pause")
        }

        /// The paused capsule's layout alone (no fill): the pause screen keeps its room with it, unseen.
        static var resumeLabel: some View {
            Text("Resume")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .fixedSize()
                .padding(.horizontal, resumePadding)
                .frame(height: resumeHeight)
        }
    }
}
