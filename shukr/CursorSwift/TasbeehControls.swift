//
//  TasbeehControls.swift
//  shukr
//
//  The session's switches on the pause screen — continuous · sleep · sets · haptics — with their pages (cleanup-map
//  tangle 5, step 5: out of `tasbeehView.pauseScreen_StatsSettingsBG`, which hands them its settings as
//  `TasbeehSwitches`). The page flags are the controls' own state now; the rest moved as it was.
//

import SwiftUI
import SwiftData

/// The session settings the switches change: bindings into the session's own (tasbeehView's @AppStorage and models).
struct TasbeehSwitches {
    var toggleInactivityTimer: Binding<Bool>
    var inactivityDimmer: Binding<Double>
    var autoStop: Binding<Bool>
    var tasbeehColorMode: Binding<Bool>
    var currentVibrationMode: Binding<HapticFeedbackType>
    /// Count in sets, this session (the counter's +N turns it on and off too).
    var countingInSets: Binding<Bool>
}

struct TasbeehControls: View {
    /// Sleep mode's one-time intro (owner, decision sleep-intro): shown until "Turn on" once.
    @AppStorage(SleepMorning.introConfirmedKey) private var sleepIntroConfirmed = false
    /// The set size: the zikr's own (`quickAddStep`), or this for sessions with no zikr.
    @AppStorage(QuickAddSteps.noMantraKey) private var noMantraSetStep = 0
    @Environment(\.modelContext) private var setsContext
    @Environment(SharedStateClass.self) var sharedState
    @State private var showSetsPage = false
    /// The page was opened by a tap with no size set: Done with a size turns sets on (owner, sets-tap).
    @State private var setsPageTurnsOn = false
    @State private var showSleepIntro = false
    @State private var showGoalIntro = false
    @Binding var toggleInactivityTimer: Bool
    @Binding var inactivityDimmer: Double
    @Binding var autoStop: Bool
    @Binding var tasbeehColorMode: Bool
    @Binding var currentVibrationMode: HapticFeedbackType
    @Binding var countingInSets: Bool
    let mantra: MantraModel?
    let appLookDark: Bool
    /// Past the goal on "continuous": the chip is locked.
    let goalReached: Bool
    /// The soft look (the switches' circles raised from the theme's material).
    let ringAbove: Bool
    /// The sleep chip's place (global): the sleep dim leaves it uncovered while paused.
    let onSleepChipFrame: (CGRect) -> Void
    /// Where the row is, for the first session's tips (CountTips).
    let onChipsFrame: (CGRect) -> Void

    init(_ switches: TasbeehSwitches, mantra: MantraModel?, appLookDark: Bool, goalReached: Bool, ringAbove: Bool,
         onSleepChipFrame: @escaping (CGRect) -> Void, onChipsFrame: @escaping (CGRect) -> Void) {
        _toggleInactivityTimer = switches.toggleInactivityTimer
        _inactivityDimmer = switches.inactivityDimmer
        _autoStop = switches.autoStop
        _tasbeehColorMode = switches.tasbeehColorMode
        _currentVibrationMode = switches.currentVibrationMode
        _countingInSets = switches.countingInSets
        self.mantra = mantra
        self.appLookDark = appLookDark
        self.goalReached = goalReached
        self.ringAbove = ringAbove
        self.onSleepChipFrame = onSleepChipFrame
        self.onChipsFrame = onChipsFrame
    }

    var body: some View { chipsRow }

    /// The session's goal for the goal page: "33" or "10 min".
    private var goalText: String {
        sharedState.selectedMode == 1 ? "\(sharedState.selectedMinutes) min" : sharedState.targetCount
    }
    /// "You have a count goal of 33" / "You have a time goal of 3 minutes" (owner: no zikr name).
    private var goalSubtitle: String {
        if sharedState.selectedMode == 1 {
            let m = sharedState.selectedMinutes
            return "You have a time goal of \(m) minute\(m == 1 ? "" : "s")"
        }
        return "You have a count goal of \(sharedState.targetCount)"
    }

    /// continuous (lit) / stops at goal (plain), sleep, haptics — each a chip, the first two with an (i).
    private var chipsRow: some View {
        HStack(spacing: 8) {
            if sharedState.selectedMode != 0 {   // freestyle has no goal to stop at
                // Locked once the goal is passed (owner): switching back ended the session the
                // moment it resumed.
                // One name, lit when on (decision chip-continuous A, owner): continuous = it keeps counting past the
                // goal; plain = it stops at the goal — like the sleep and haptics chips beside it.
                chip("continuous", icon: "arrow.clockwise", on: !autoStop, locked: goalReached,
                     info: ("About continuous", { showGoalIntro = true }), onHold: { showGoalIntro = true }) { autoStop.toggle() }
                .fullScreenCover(isPresented: $showGoalIntro) {
                    GoalIntroView(autoStop: $autoStop, locked: goalReached, goal: goalText,
                                  subtitle: goalSubtitle) { showGoalIntro = false }
                }
            }
            // Where its circle is, for the dim to leave it uncovered (always findable to turn sleep off — owner);
            // (i) by it: the intro again, any time (owner).
            chip("sleep", icon: toggleInactivityTimer ? "moon.zzz.fill" : "moon.zzz", on: toggleInactivityTimer,
                 info: ("About sleep mode", { showSleepIntro = true }), onHold: { showSleepIntro = true },
                 circleFrame: onSleepChipFrame) {
                // The first time (until confirmed once): the intro, which turns it on.
                if !toggleInactivityTimer && !sleepIntroConfirmed { showSleepIntro = true; return }
                toggleInactivityTimer.toggle()
                // On: dark. Off: back to the app's own look (there's no light / dark chip).
                tasbeehColorMode = toggleInactivityTimer ? true : appLookDark
            }
            .fullScreenCover(isPresented: $showSleepIntro) {
                SleepIntroView(isOn: toggleInactivityTimer, dimmer: $inactivityDimmer, onTurnOn: {
                    sleepIntroConfirmed = true
                    toggleInactivityTimer = true
                    tasbeehColorMode = true
                    showSleepIntro = false
                }, onNotNow: { showSleepIntro = false })
                .interactiveDismissDisabled()
            }
            setsChip
            hapticsChip
        }
        // Where they are, for the first session's tips (CountTips).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onChipsFrame($0) }
    }

    private var setStep: Int { mantra?.quickAddStep ?? noMantraSetStep }

    private var setStepBinding: Binding<Int> {
        Binding(get: { setStep }, set: { newValue in
            if let mantra {
                mantra.quickAddStep = newValue
                try? setsContext.save()
            } else {
                noMantraSetStep = newValue
            }
            if newValue <= 1 { countingInSets = false }
        })
    }

    /// Count in sets (decisions sets-place A, sets-tap): with a size set a tap turns it on or off, as the counter's
    /// +N does; with none, a tap opens its page to pick one (Done then turns it on). A hold opens the page any time.
    private var setsChip: some View {
        let size = setStep
        // (i) on its shoulder too, like continuous and sleep (owner: "I still don't see the info sheet on the set
        // button"): its page, the same as a hold.
        return roundSwitch(size > 1 ? "sets of \(size)" : "count in sets", on: countingInSets && size > 1,
                           info: ("About count in sets", { setsPageTurnsOn = false; showSetsPage = true }),
                           onHold: { setsPageTurnsOn = false; showSetsPage = true }, action: {
            if size > 1 {
                countingInSets.toggle()
            } else {
                setsPageTurnsOn = true
                showSetsPage = true
            }
        }) {
            if size > 1 {
                Text("+\(size)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
            } else {
                Image(systemName: "square.stack")
                    .font(.system(size: 19, weight: .light))
            }
        }
        .fullScreenCover(isPresented: $showSetsPage) {
            CountInSetsPage(step: setStepBinding, zikrName: mantra?.name) {
                if setsPageTurnsOn && setStep > 1 { countingInSets = true }
                showSetsPage = false
            }
        }
    }

    /// The phone with waves either side: one wave lit for light taps, two for medium, all
    /// three for strong (the symbols' variable value). A change only steps the lit waves to
    /// the new level (owner, A1399C45: the full inner-to-outer ripple on every tap was too long);
    /// the phone stays still (owner, A7B8CB0A: "the waves is enough"). Silent: the waves fade out;
    /// back to light, the first returns.
    private var hapticsChip: some View {
        let level: Double = switch currentVibrationMode {
        case .off: 0
        case .light: 0.2     // a wave lights once the value passes 0, ⅓, ⅔
        case .heavy: 1
        default: 0.5
        }
        return roundSwitch(hapticLabel, on: false, faded: currentVibrationMode == .off, action: cycleHaptics) {
            // Our own "iphone.radiowaves": the phone between two three-wave symbols
            // (the stock one has only two waves a side, so medium = strong).
            HStack(spacing: 1) {
                Image(systemName: "wave.3.left", variableValue: level)
                    .opacity(currentVibrationMode == .off ? 0 : 1)
                Image(systemName: "iphone")
                    .font(.system(size: 18, weight: .light))
                Image(systemName: "wave.3.right", variableValue: level)
                    .opacity(currentVibrationMode == .off ? 0 : 1)
            }
            .font(.system(size: 11, weight: .regular))
            .symbolRenderingMode(.hierarchical)
        }
    }

    private var hapticLabel: String {
        switch currentVibrationMode {
        case .off: return "silent"
        case .light: return "light taps"
        case .heavy: return "strong taps"
        default: return "medium taps"
        }
    }

    private func cycleHaptics() {
        switch currentVibrationMode {
        case .off: currentVibrationMode = .light
        case .light: currentVibrationMode = .medium
        case .medium: currentVibrationMode = .heavy
        case .heavy: currentVibrationMode = .off
        default: currentVibrationMode = .medium
        }
        triggerSomeVibration(type: currentVibrationMode)
    }

    /// A labelled setting: symbol over a short word, soft tile; sage while on.
    /// A chip's (i) in its top-right corner: opens its explainer page; its own tap target, so the
    /// chip underneath doesn't switch.
    private func infoButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            // A bigger target (owner: "if you miss a little then it unpauses"), grown up and outwards, away from
            // its switch's circle: ~42 × 36 pt instead of 26, overlapping only the circle's top-right edge.
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(on ? Color.sage.opacity(0.8) : Color.primary.opacity(0.4))
                .padding(.top, Self.infoReach)
                .padding(.trailing, Self.infoReach)
                .padding(.leading, 12)
                .padding(.bottom, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func chip(_ title: String, icon: String, on: Bool, locked: Bool = false,
                      info: (label: String, open: () -> Void)? = nil, onHold: (() -> Void)? = nil,
                      circleFrame: ((CGRect) -> Void)? = nil, action: @escaping () -> Void) -> some View {
        roundSwitch(title, on: on, locked: locked, info: info, onHold: onHold, circleFrame: circleFrame, action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .light))
                .contentTransition(.symbolEffect(.replace))
        }
    }

    /// A session switch: a circle with its symbol, its word under it (decision stats-weight A — never the stat tiles'
    /// shape, so a switch never reads as a number). Sage while on. It's the circle and the word, no wider: the page
    /// round it still resumes. Its (i), when it has one, sits on the circle's shoulder, its own tap. A hold opens its
    /// page when it has one (owner, sets-tap: "on any of them that open a sheet … long pressing it opens that sheet").
    private func roundSwitch<Icon: View>(_ title: String, on: Bool, faded: Bool = false, locked: Bool = false,
                                         info: (label: String, open: () -> Void)? = nil,
                                         onHold: (() -> Void)? = nil,
                                         circleFrame: ((CGRect) -> Void)? = nil,
                                         action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        let tap = {
            guard !locked else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.snappy(duration: CircleMotion.quick)) { action() }
        }
        // A tap and a hold on one view (not a Button with a hold beside it: a Button still fires on the hold's release).
        return VStack(spacing: 7) {
            icon()
                .foregroundStyle(on ? Color.sage : Color.primary.opacity(faded ? 0.45 : 0.75))
                .frame(width: Self.switchCircle, height: Self.switchCircle)
                .background {
                    if on {
                        Circle().fill(Color.sage.opacity(0.16))
                    } else if ringAbove {
                        ThemedRaised(shape: Circle(), radius: 5, offset: 2.5)
                    } else {
                        Circle().fill(Color.primary.opacity(0.06))
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { circleFrame?($0) }
            Text(title)
                .font(.caption2)
                .foregroundStyle(on ? Color.sage : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)
        }
        .contentShape(Rectangle())
        .opacity(locked ? 0.45 : 1)
        .onTapGesture(perform: tap)
        .onLongPressGesture(minimumDuration: 0.4) {
            if let onHold {
                triggerSomeVibration(type: .medium)
                onHold()
            } else {
                tap()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, tap)
        .accessibilityHint(locked ? "Locked once the goal is reached" : "")
        .overlay(alignment: .top) {
            if let info {
                // The icon where it was (on the circle's shoulder); its bigger target reaches up and right.
                infoButton(info.label, on: on, action: info.open)
                    .offset(x: Self.switchCircle / 2 + 4 + (Self.infoReach - 12) / 2, y: -9 - (Self.infoReach - 7))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static let switchCircle: CGFloat = 50
    /// How far an (i)'s target reaches above and to the right of its icon.
    private static let infoReach: CGFloat = 18
}
