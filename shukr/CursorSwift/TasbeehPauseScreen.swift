//
//  TasbeehPauseScreen.swift
//  shukr
//
//  The session's pause screen — the soft look, the bottom block it shares with the results, the zikr card and the
//  controls — nested in `tasbeehView` as before (an extension: same name, same code). Moved out of tasbeehView.swift
//  (cleanup-map tangle 5, step 2).
//

import SwiftUI
import SwiftData
import AVFAudio

extension tasbeehView {
    /// The pause screen (redesigned 2026-09-25 — owner: the bottom buttons "didn't feel on
    /// brand", keep the bento, and make the mantra's full text and notes reachable). Top to
    /// bottom: "paused · 33 count session", the mantra card (name → picker, the full mantra, notes,
    /// its quick-add step, ✎ → the mantra's page), the stats bento, the finish estimate, then
    /// labelled setting chips and Finish / Resume. Tapping the dimmed background still resumes.
    struct pauseScreen_StatsSettingsBG: View {
        /// Sleep mode's one-time intro (owner, decision sleep-intro): shown until "Turn on" once.
        @AppStorage(SleepMorning.introConfirmedKey) private var sleepIntroConfirmed = false
        /// The set size: the zikr's own (`quickAddStep`), or this for sessions with no zikr.
        @AppStorage(QuickAddSteps.noMantraKey) private var noMantraSetStep = 0
        @Environment(\.modelContext) private var setsContext
        private var showSetsPage: Bool { get { ui.showSetsPage } nonmutating set { ui.showSetsPage = newValue } }
        /// The page was opened by a tap with no size set: Done with a size turns sets on (owner, sets-tap).
        private var setsPageTurnsOn: Bool { get { ui.setsPageTurnsOn } nonmutating set { ui.setsPageTurnsOn = newValue } }
        private var showSleepIntro: Bool { get { ui.showSleepIntro } nonmutating set { ui.showSleepIntro = newValue } }
        private var showGoalIntro: Bool { get { ui.showGoalIntro } nonmutating set { ui.showGoalIntro = newValue } }
        @Environment(SharedStateClass.self) var sharedState
        /// The screen's own state in one @Observable (cleanup-map tangle 5, step 4); the properties below forward to it.
        @State private var ui = PauseScreenState()
        let paused: Bool
        let mantra: MantraModel?
        let tasbeeh: Int
        let secsToReport: TimeInterval
        let newAvrgTPC: TimeInterval
        let tasbeehRate: String
        let togglePause: () -> Void
        let stopTimer: () -> Void
        let takingNotes: Bool
        @Binding var toggleInactivityTimer: Bool
        @Binding var inactivityDimmer: Double
        @Binding var autoStop: Bool
        @Binding var tasbeehColorMode: Bool
        let appLookDark: Bool
        /// Past the goal on "continuous": the chip is locked and Finish isn't "early".
        let goalReached: Bool
        @Binding var currentVibrationMode: HapticFeedbackType
        /// Count in sets, this session (the counter's +N turns it on and off too).
        @Binding var countingInSets: Bool
        /// The ring-above layout (decision session-flow-build A): the counter's ring stays on screen, raised, and these
        /// cards sit round it; the same cards carry the results, the ring centred. Classic (Today's) keeps `todayBody`.
        /// The surfaces come from the theme's material (ThemedRaised / ThemedPressed).
        var ringAbove = false
        /// Seconds already done today when continuing a timed task (the "left" tile counts them).
        var timeOffset: TimeInterval = 0
        /// The finished session, under the soft look.
        var results: SoftResults? = nil
        /// The tiles and buttons are up: paused, the results in, or finishing from the pause screen (they hold still
        /// through it — only the ring moves).
        var cardsShown = false
        /// The results' words are in (after the counter's have gone).
        var resultsIn = false
        /// Where the ring stands while paused (global), and the bottom block's top (global): the session moves its ring.
        var onRingSlot: (CGRect) -> Void = { _ in }
        var onBottomTop: (CGFloat) -> Void = { _ in }
        /// The sleep chip's place (global): the sleep dim leaves it uncovered while paused.
        var onSleepChipFrame: (CGRect) -> Void = { _ in }
        var onChipsFrame: (CGRect) -> Void = { _ in }
        /// The counter's top bar's height: the pause screen's top row matches it, so ‹ Resume lands where ⏸ was.
        var topBarHeight: CGFloat = 0

        /// What the soft cards need of a finished session.
        struct SoftResults {
            let session: SessionDataModel
            var keepCounting: (() -> Void)?
            let done: () -> Void
        }

        // UI state
        private var showHistory: Bool { get { ui.showHistory } nonmutating set { ui.showHistory = newValue } }
        private var wellRoom: CGFloat { get { ui.wellRoom } nonmutating set { ui.wellRoom = newValue } }
        /// The well's words' own height: the well is no taller than them (the space under it is the page's, not an
        /// empty well), and shrinks to scroll them where the page is short.
        private var wellTextHeight: CGFloat { get { ui.wellTextHeight } nonmutating set { ui.wellTextHeight = newValue } }
        /// The well's scroll: at the top for a new zikr or a new height.
        /// Stays the view's own @State, not in PauseScreenState: the ScrollView writes its position back through this
        /// binding, and from an @Observable each write invalidated the screen and re-ran the scroll request — a loop at
        /// 100 % CPU that froze the app (Fable's sim, 2026-10-20).
        @State private var wellScroll = ScrollPosition(edge: .top)
        /// The zikr's own page, opened by a tap on its card.
        /// The zikr's card editor over the pause screen.
        private var cardEditing: ZikrCardRequest? { get { ui.cardEditing } nonmutating set { ui.cardEditing = newValue } }
        private var bottomInset: CGFloat { get { ui.bottomInset } nonmutating set { ui.bottomInset = newValue } }
        /// The page's height inside the safe area: how much room the gaps get (`airScale`).
        private var pageHeight: CGFloat { get { ui.pageHeight } nonmutating set { ui.pageHeight = newValue } }
        /// The rate tile's side: per count, or per tasbeeh (a tap flips it).
        private var showingPerTasbeeh: Bool { get { ui.showingPerTasbeeh } nonmutating set { ui.showingPerTasbeeh = newValue } }
        /// The two rate numbers' opacities, each changed in its own animation (a quick fade out, a gentler fade in) —
        /// one transaction for the whole flip gave both the spring's length, and they overlapped.
        private var perCountOpacity: Double { get { ui.perCountOpacity } nonmutating set { ui.perCountOpacity = newValue } }
        private var perTasbeehOpacity: Double { get { ui.perTasbeehOpacity } nonmutating set { ui.perTasbeehOpacity = newValue } }
        /// Finish (the counter's −, changed in place — MinusFinishButton) is asking for its second tap: the session's
        /// line steps aside for its words.
        var finishArmed = false
        private var showMantraPicker: Bool { get { ui.showMantraPicker } nonmutating set { ui.showMantraPicker = newValue } }
        private var chosenMantraName: String? { get { ui.chosenMantraName } nonmutating set { ui.chosenMantraName = newValue } }
        private var chosenMantraObject: MantraModel? { get { ui.chosenMantraObject } nonmutating set { ui.chosenMantraObject = newValue } }
        private var fullTextExpanded: Bool { get { ui.fullTextExpanded } nonmutating set { ui.fullTextExpanded = newValue } }

        // Computed variables for est time completion (only for target count mode)
        private var remainingCount: Int{
            return (Int(sharedState.targetCount) ?? 0) - Int(tasbeeh)
        }
        private var timeLeft : TimeInterval{
            return newAvrgTPC * Double(remainingCount)
        }

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

        /// Count goal, not post-salah, started and not done: the bento adds the finish tile.
        private var showsFinishEstimate: Bool {
            sharedState.selectedMode == 2 && remainingCount > 0 && !sharedState.isDoingPostNamazZikr && tasbeeh > 0
        }

        private var sessionLabel: String {
            switch sharedState.selectedMode {
            case 1: return "\(sharedState.selectedMinutes) min session"
            case 2: return "\(sharedState.targetCount) count session"
            default: return "freestyle session"
            }
        }

        /// Launched from a task card: the session counts toward that task, so its mantra stays
        /// (same rule as `saveSession`'s task link).
        private var isTaskSession: Bool {
            sharedState.selectedMode != 0 && !sharedState.isDoingPostNamazZikr && sharedState.selectedTask != nil
        }
        /// Task and post-salah sessions keep their mantra; only free sessions can switch.
        private var mantraLocked: Bool { isTaskSession || sharedState.isDoingPostNamazZikr }

        /// The task's streak and best (owner, 2026-10-08: "if we have a streak and max streak display it"), in the
        /// results' words: a sage flame once today is done, a grey one while it's still to keep. Nothing without one.
        private var shownTaskStreak: TaskStreak? {
            #if DEBUG
            // -demoTaskStreak "current,best,kept" (e.g. "7,21,0") fakes the line for a look check.
            if let fake = UserDefaults.standard.string(forKey: "demoTaskStreak") {
                let n = fake.split(separator: ",").compactMap { Int($0) }
                if n.count == 3 { return TaskStreak(current: n[0], best: n[1], keptToday: n[2] == 1) }
            }
            #endif
            return sharedState.selectedTask?.streak()
        }
        @ViewBuilder private func taskStreakLine(_ font: Font) -> some View {
            if isTaskSession, let streak = shownTaskStreak, streak.current > 0 {
                HStack(spacing: 4) {
                    Image(systemName: streak.keptToday ? "flame.fill" : "flame")
                        .foregroundStyle(streak.keptToday ? Color.sage : Color.secondary)
                    Text(streak.current >= streak.best ? "\(streak.current)-day streak · your best"
                                                       : "\(streak.current)-day streak · best \(streak.best)")
                        .foregroundStyle(.secondary)
                }
                .font(font)
                .accessibilityElement(children: .combine)
            }
        }

        private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
        /// The pause card's scroll view height: its content fills it, so empty space there resumes.
        private var scrollHeight: CGFloat { get { ui.scrollHeight } nonmutating set { ui.scrollHeight = newValue } }

        var body: some View {
            Group {
                if ringAbove { softBody } else { todayBody }
            }
            // The session tour skips its finish-time tip when there's none (a freestyle session).
            .onChange(of: showsFinishEstimate, initial: true) { _, shown in CountTips.shared.finishShown = shown }
        }

        @ViewBuilder private var todayBody: some View {
            Color("pauseColor")
                .edgesIgnoringSafeArea(.all)
                .animation(.easeOut(duration: 0.3), value: paused)
                .opacity(paused ? 1 : 0.0)
                .onTapGesture { togglePause() }
                .allowsHitTesting(paused)

            VStack(spacing: 0) {
                pauseTopRow

                ScrollView {
                    VStack(spacing: 12) {
                        // Tasbih Fatimah is its own thing (owner): the three phrases and where the
                        // count is, instead of the mantra card (no edit, no count-in-sets).
                        if sharedState.isDoingPostNamazZikr {
                            PostSalahPauseCard(count: tasbeeh)
                        } else {
                            mantraCard
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.notes", $0) }
                        }
                        ZikrBento(count: tasbeeh, seconds: secsToReport, secondsPerCount: newAvrgTPC,
                                  perTasbeeh: tasbeehRate,
                                  finishIn: showsFinishEstimate ? timeLeft : nil,
                                  usualSecondsPerCount: mantra?.secondsPerCount)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.stats", $0) }
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    // The empty space round and under the cards resumes too (owner): the scroll view
                    // took every tap in its frame. Behind the cards, so a tap on one stays on it.
                    .frame(minHeight: scrollHeight, alignment: .top)
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture { togglePause() })
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }

                controls
            }
            .fontDesign(.rounded)
            .opacity(paused ? 1.0 : 0.0)
            .animation(.easeInOut, value: paused)
            .allowsHitTesting(paused)
            .onChange(of: chosenMantraName) {
                if let newSetMantra = chosenMantraName, !newSetMantra.isEmpty {
                    withAnimation {
                        sharedState.mantraForSession = chosenMantraObject
                        sharedState.titleForSession = newSetMantra
                        fullTextExpanded = false
                    }
                }
            }
            .sheet(isPresented: Bindable(ui).showMantraPicker) {
                MantraPickerView(
                    isPresented: Bindable(ui).showMantraPicker,
                    selectedMantra: Bindable(ui).chosenMantraName,
                    selectedMantraObject: Bindable(ui).chosenMantraObject,
                    presentation: [.large]
                )
            }
        }

        // MARK: soft look (decision session-flow-build A)

        /// Paused, not finished: the pause screen's own words (header, name, text well, chips) are up.
        private var pauseShown: Bool { paused && results == nil }

        /// The soft pause screen and results, one layout: the counter's ring stays on screen — raised while paused
        /// (`onRingSlot`), centred once finished — and the tiles and buttons at the bottom are the same on both, so
        /// finishing from the pause screen moves only the ring. The page doesn't scroll: a long zikr scrolls inside
        /// its fixed well.
        @ViewBuilder private var softBody: some View {
            ZStack {
                // The empty page resumes (as the dimmed background did).
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { togglePause() }
                    .allowsHitTesting(pauseShown)

                VStack(spacing: 0) {
                    pauseTopRow
                    // The zikr's whole card at the top (owner, 2026-10-08: "show the full thing … push it to the top. then
                    // spacer. then the other stuff at the bottom") — the ring's room is now the card's and the space.
                    gap(12)
                    VStack(spacing: 10) {
                        // Out of sight, the well can't hold the name: it sits above it then (Bradley's review of b496df7).
                        if !wellHoldsName || !wellShows { softNameRow }
                        // As tall as its words, up to most of the page (long ones scroll inside it); with too little
                        // room for its text (a small phone, the largest text) it stays out of sight rather than
                        // squeezed — and takes no taps then.
                        softWell
                            .opacity(wellShows ? 1 : 0)
                            .allowsHitTesting(wellShows)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { wellRoom = $0 }
                            .layoutPriority(1)
                    }
                    // A tap among the zikr's name, its media and its text never resumes (only the page round them does):
                    // a near-miss on ▶︎ resumed the session (owner). A tap on the card opens just the zikr's card editor,
                    // floating over the blurred pause screen (owner; it opened the zikr's whole page before); its name,
                    // ▶︎ and photo keep their own taps. No delete from inside a session.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard let mantra, !sharedState.isDoingPostNamazZikr else { return }
                        triggerSomeVibration(type: .light)
                        cardEditing = ZikrCardRequest(mantra: mantra)
                    }
                    .zikrCardEditor(Bindable(ui).cardEditing, allowDelete: false, blursPage: true)
                    .modifier(PauseLayerFade(shown: pauseShown, finishing: results != nil, resultsDelay: 0.22))
                    .allowsHitTesting(pauseShown)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.notes", $0) }
                    // The room left over, between the card and the tiles.
                    Spacer(minLength: 24)
                    softBottom
                        // The session tour's stats tip sits above the tiles (their top is this block's top).
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.stats", $0) }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                // Finish early off the edge where there's no home indicator (an SE); elsewhere the safe area does it.
                // On a phone with a home indicator, down into its band (owner: the empty space under the switches),
                // the switches' words staying clear of it; an SE keeps 6 pt off its edge.
                .padding(.bottom, bottomInset > 0 ? -(bottomInset - 20) : 6)
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            .fontDesign(.rounded)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)   // fixed slots: past this the tiles and chips truncated
            .onChange(of: chosenMantraName) {
                if let newSetMantra = chosenMantraName, !newSetMantra.isEmpty {
                    withAnimation {
                        sharedState.mantraForSession = chosenMantraObject
                        sharedState.titleForSession = newSetMantra
                    }
                }
            }
            .sheet(isPresented: Bindable(ui).showMantraPicker) {
                MantraPickerView(
                    isPresented: Bindable(ui).showMantraPicker,
                    selectedMantra: Bindable(ui).chosenMantraName,
                    selectedMantraObject: Bindable(ui).chosenMantraObject,
                    presentation: [.large]
                )
            }
            .sheet(isPresented: Bindable(ui).showHistory) {
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

        /// The pause screen's top row, where the counter's bar is (decision top-bar-finish A, owner: "move the resume and
        /// finish early buttons out from the bottom"): ‹ Resume in ⏸'s place, the session in the middle, Finish on the
        /// right — two taps, as Finish early was. On the soft results, Done in Finish's place. As tall as the counter's
        /// bar (`topBarHeight`), so ‹ Resume lands where ⏸ was.
        private var pauseTopRow: some View {
            let finished = results != nil
            return HStack(spacing: 8) {
                // ‹ Resume itself is the counter's ⏸, changed in place (PauseResumeButton, in the top bar over this
                // row); its twin here, unseen, keeps the session line clear of it.
                ZStack(alignment: .leading) {
                    PauseResumeButton.resumeLabel
                        .hidden()
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 4)
                // The session between them (never over them: centred on the page it ran into ‹ Resume on a 6.1"
                // phone); out of the way while Finish asks for its second tap.
                // A task's streak and best under it (owner: moved up here from under "from your task").
                VStack(spacing: 1) {
                    Text(sharedState.isDoingPostNamazZikr ? "Tasbih Fatimah" : sessionLabel)
                        .font(.subheadline.weight(.light))
                        .foregroundStyle(.secondary)
                    taskStreakLine(.caption2)
                }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .opacity(finishArmed ? 0 : 1)
                    .modifier(PauseLayerFade(shown: pauseShown, finishing: results != nil, resultsDelay: 0.22))
                    .allowsHitTesting(false)
                    .layoutPriority(-1)
                Spacer(minLength: 4)
                ZStack(alignment: .trailing) {
                    // Finish itself is the counter's −, changed in place (MinusFinishButton, in the top bar over this
                    // row); its twin here, unseen, keeps the session line clear of it.
                    MinusFinishButton.finishLabel
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: finishArmed)
            // 16 from the screen's edges, as the counter's bar: the soft page already insets its column by 20.
            .padding(.horizontal, ringAbove ? -4 : 16)
            .frame(height: max(topBarHeight, 44))
        }

        /// Under the ring: the zikr's name (→ the picker on a free session), "from your task", its memo and photo.
        private var softNameRow: some View {
            let title = sharedState.isDoingPostNamazZikr ? PostSalahTasbeeh.mantraName : sharedState.titleForSession
            return VStack(spacing: 2) {
                Button { showMantraPicker = true } label: {
                    HStack(spacing: 6) {
                        Text(title.isEmpty ? "choose a zikr" : title)
                            .font(.system(size: 24, weight: .light, design: .rounded))
                            .foregroundStyle(title.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !mantraLocked {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!mantraLocked)   // not .disabled: that grayed the name out
                HStack(spacing: 12) {
                    if sharedState.isDoingPostNamazZikr {
                        Text("33 · 33 · 34 after salah")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isTaskSession {
                        Label(sharedState.selectedTask?.title ?? "your goal", systemImage: "target")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let mantra, !sharedState.isDoingPostNamazZikr {
                        ZikrMediaStrip(mantra: mantra, paused: paused, compact: true)
                    }
                }
                .frame(minHeight: 24)
            }
        }

        /// The zikr's name — with "from your task", the memo and the photo at its right — at the top of the well, the
        /// full text and the notes under it, rules between them; no row under the ring (owner, decision
        /// pause-name-in-well: "fit it INTO the already given area of the well" — the well's size is unchanged).
        /// Tasbih Fatimah keeps its own row and card.
        private var wellHoldsName: Bool { !sharedState.isDoingPostNamazZikr }
        /// The well has room for its text (else it's out of sight and the name row sits above it).
        private var wellShows: Bool { wellRoom >= Self.wellShowsAt }

        /// The well's top when it holds the name: the name (the picker on a free session), "from your task" under it,
        /// the memo and photo on the right; a rule under it. It stays put while the text scrolls.
        private var wellNameHeader: some View {
            let title = sharedState.titleForSession
            return HStack(alignment: .center, spacing: 10) {
                Button { showMantraPicker = true } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            // A long nickname wraps to a second line before anything is cut (one line shrank it to
                            // nothing and cut it off — owner's "Allahu la ilaha illalahu …").
                            Text(title.isEmpty ? "choose a zikr" : title)
                                .font(.system(size: 19, weight: .light, design: .rounded))
                                .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.leading)
                            if !mantraLocked {
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if isTaskSession {
                            Label(sharedState.selectedTask?.title ?? "your goal", systemImage: "target")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .allowsHitTesting(!mantraLocked)
                Spacer(minLength: 8)
                if let mantra {
                    ZikrMediaStrip(mantra: mantra, paused: paused, compact: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }

        private var wellRule: some View {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }

        /// The zikr's full text and notes in a well pressed into the page, a fixed height: long ones scroll inside it.
        /// Count in sets is its last row, as it was the card's.
        private var softWell: some View {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            return VStack(spacing: 0) {
                if wellHoldsName {
                    wellNameHeader
                    wellRule.padding(.horizontal, 14)
                }
                ScrollView {
                    Group {
                        if sharedState.isDoingPostNamazZikr {
                            PostSalahPauseCard(count: tasbeeh, bare: true)
                        } else {
                            softWellText
                                // 18 above (the Uthmani face's marks over the first line reach past its line box; 12
                                // clipped them), 16 below: the text sits in the middle of its space (owner).
                                .padding(.top, 18)
                                .padding(.bottom, 16)
                                .padding(.horizontal, 14)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { h in
                        if abs(h - wellTextHeight) >= 1 { wellTextHeight = h }
                    }
                }
                .frame(maxHeight: wellTextHeight > 0 ? min(wellTextHeight, 380) : nil)   // longer: it scrolls
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                // The well keeps its room (owner: "still make the sunken well take up all the space"); its parts stack from
                // the top, each as tall as it is — the text in the middle of its own space, the note under it, the
                // rest of the room below them (owner: "he just needs a little vertical space since its one line").
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.top, for: .initialOffset)  // a long one starts at its top…
                // …and is put back there whenever the well's height settles (it opened mid-zikr on a 6.1" phone: the
                // well finds its height after the first layout, and the default anchors didn't hold through that).
                .scrollPosition($wellScroll)
                .onChange(of: wellRoom) { _, _ in wellScroll.scrollTo(edge: .top) }
                .onChange(of: mantra?.id) { _, _ in wellScroll.scrollTo(edge: .top) }

                // (Count in sets is a switch under the tiles now — decision sets-place A: the well keeps its room
                // for the zikr's text and notes, so they show on a 6.1" phone too.)
            }
            .background(ThemedPressed(shape: shape))
            .clipShape(shape)
        }

        @ViewBuilder private var softWellText: some View {
            if let mantra {
                let full = mantra.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                let notes = mantra.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                VStack(spacing: 10) {
                    if !full.isEmpty {
                        // Arabic lines in the Uthmani face, the rest (transliteration, meaning) in the light rounded type.
                        VStack(spacing: 6) {
                            ForEach(Array(full.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                let text = line.trimmingCharacters(in: .whitespaces)
                                if !text.isEmpty {
                                    let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
                                    Text(text)
                                        .font(arabic ? .custom("KFGQPCUthmanTahaNaskh", size: 26) : .system(size: 15, weight: .light, design: .rounded))
                                        .foregroundStyle(arabic ? .primary : .secondary)
                                        .lineSpacing(arabic ? 8 : 2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                    }
                    if !notes.isEmpty && wellHoldsName && !full.isEmpty { wellRule.padding(.vertical, 4) }
                    if !notes.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                            BulletedNotes(text: notes)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                    }
                    if full.isEmpty && notes.isEmpty {
                        Text("no full text or notes yet — add them on its page")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text(sharedState.titleForSession.isEmpty ? "its full text and notes show up here" : "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        // MARK: soft bottom block — the same on the pause screen and the results

        /// The finished session's values once it's saved, else the running session's.
        private var shownSeconds: TimeInterval { results?.session.secondsPassed ?? secsToReport }
        private var shownPerCount: Double { results?.session.avgTimePerClick ?? newAvrgTPC }
        private var shownPerTasbeeh: String { results?.session.tasbeehRate ?? tasbeehRate }
        private var shownUsualPace: Double? {
            if let s = results?.session { return s.mantra?.secondsPerCount(excluding: s) }
            return mantra?.secondsPerCount
        }

        /// The third tile while paused: what's left (a count goal: time left ⇄ the finish time; a time goal: time left
        /// ⇄ when it ends), else the pace per tasbeeh (freestyle, Tasbih Fatimah, past the goal).
        private enum ThirdTile { case left(TimeInterval), toGo(Int), counted }
        private var thirdTile: ThirdTile {
            if !sharedState.isDoingPostNamazZikr && !goalReached {
                if sharedState.selectedMode == 2 && remainingCount > 0 {
                    return tasbeeh > 0 && newAvrgTPC > 0 ? .left(timeLeft) : .toGo(remainingCount)
                }
                if sharedState.selectedMode == 1 {
                    let left = max(0, Double(sharedState.selectedMinutes * 60) - secsToReport - timeOffset)
                    if left > 0 { return .left(left) }
                }
            }
            return .counted
        }

        private var softBottom: some View {
            let finished = results != nil
            let pace = ZikrBento.paceComparison(secondsPerCount: shownPerCount, usual: shownUsualPace, perCount: true)
            let pacePerTasbeeh = ZikrBento.paceComparison(secondsPerCount: shownPerCount, usual: shownUsualPace, perCount: false)
            // The old pause screen's bento (decision stats-weight A): time and count small with their symbols, the rate
            // tall beside them — the rate weighs most; the finish a sentence under them, not a tile. Room round each
            // part (owner: "enough room to breathe … the stuff around the tiles").
            return VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(spacing: 10) {
                        softStatTile(icon: "gauge.with.needle") {
                            softStatLines(timerStyle(shownSeconds), "time")
                        }
                        softStatTile(icon: "circle.hexagonpath") {
                            ZStack(alignment: .leading) {
                                softStatLines(tasbeeh.formatted(), "count")
                                    .modifier(SoftCardsFade(shown: !finished, delay: 0))
                                softStatLines((results?.session.totalCount ?? 0).formatted(), "counted")
                                    .modifier(SoftCardsFade(shown: finished, delay: 0.1))
                            }
                        }
                    }
                    // How it compares with your usual pace inside it (owner: "the comparison text … to be in the rate
                    // tile"); flips per count ⇄ per tasbeeh (100 counts) on a tap (owner: "we lost per tasbeeh rate").
                    Button {
                        triggerSomeVibration(type: .medium)
                        let toTasbeeh = !showingPerTasbeeh
                        withAnimation(CircleMotion.label) { showingPerTasbeeh = toTasbeeh }   // move, size, captions
                        withAnimation(CircleMotion.flipOut) {
                            if toTasbeeh { perCountOpacity = 0 } else { perTasbeehOpacity = 0 }
                        }
                        withAnimation(CircleMotion.flipIn) {
                            if toTasbeeh { perTasbeehOpacity = 1 } else { perCountOpacity = 1 }
                        }
                    } label: {
                        softRateTile(pace: pace, pacePerTasbeeh: pacePerTasbeeh)
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: Self.statTileHeight * 2 + 10)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { onBottomTop($0) }
                // On the results the tiles rise a little, away from the button under them (owner: "let the different
                // sections breathe"); measured before, so the ring's room is counted from where they were.
                .offset(y: finished && resultsIn ? -resultsTilesLift : 0)
                .animation(.easeInOut(duration: CircleMotion.standard), value: finished && resultsIn)

                // The chips while paused; after a sleep finish, Keep counting in their place. More air above them than
                // the other gaps (owner: "more space to breathe between time text and feature buttons").
                gap(28)   // a little more air between the stats and the switches (owner, 2026-10-08)
                ZStack {
                    if !sharedState.isDoingPostNamazZikr {
                        chipsRow
                            .modifier(PauseLayerFade(shown: pauseShown, finishing: results != nil))
                            .allowsHitTesting(pauseShown)
                    }
                    if let results {
                        // Done back at the bottom, the capsule it was (owner: "the done button can still stay at the
                        // bottom like how we had it before"), View zikr history under it — in the switches' room.
                        VStack(spacing: 2) {
                            // After a sleep finish the button is Keep counting, not Done (owner: "if they're up they
                            // prolly wanna keep counting. if they done reading, they prolly asleep").
                            Button {
                                if let keepCounting = results.keepCounting {
                                    keepCounting()
                                } else {
                                    triggerSomeVibration(type: .success)
                                    results.done()
                                }
                            } label: {
                                Group {
                                    if results.keepCounting != nil {
                                        Label("Keep counting", systemImage: "play.fill")
                                    } else {
                                        Text("Done")
                                    }
                                }
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.sage)
                                .frame(width: 210, height: 44)
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("ct.done", $0) }
                                .background(Capsule().fill(Color.sage.opacity(0.08)))
                                .overlay(Capsule().strokeBorder(Color.sage.opacity(0.9), lineWidth: 1.5))
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Button {
                                triggerSomeVibration(type: .light)
                                showHistory = true
                            } label: {
                                Label("View zikr history", systemImage: "clock.arrow.circlepath")
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // History is the Zikr tab's: shut while it's locked (ZikrLock).
                            .opacity(ZikrLock.shared.locked ? 0 : 1)
                            .disabled(ZikrLock.shared.locked)
                        }
                        // Lower than the switches sat, and — like the tiles — as high as with a finish line, so every
                        // results screen has it in the same place.
                        .offset(y: Self.resultsButtonDrop - (hasFinishLine ? 0 : finishLineRoom))
                        .modifier(SoftCardsFade(shown: resultsIn, delay: 0.1))
                        .allowsHitTesting(resultsIn)
                    }
                }
                .frame(height: Self.switchHeight)
                // "3m 15s left · you'll finish around 3:14 PM": one sentence, not two time tiles (owner). Its room is kept
                // through the results (Done stays put); a session with no goal has none.
                // Under the switches, at the very bottom (owner: "lets see what it looks like if we shift it to the
                // bottom").
                if hasFinishLine {
                    gap(26)   // apart from the switches (owner)
                    finishLine
                        .frame(height: 22)
                        .modifier(SoftCardsFade(shown: !finished, delay: 0))
                }
                // (Resume, Finish and Done are up top now, where the counter's ⏸ is — decision top-bar-finish A.)
                gap(12)
            }
            .modifier(PauseLayerFade(shown: cardsShown, finishing: results != nil, resultsDelay: 0.12))
            .animation(.snappy(duration: 0.25), value: toggleInactivityTimer)
        }

        private static let statTileHeight: CGFloat = 52
        /// How far the tiles rise on the results: 24, plus — for a session with no finish line (freestyle, Tasbih
        /// Fatimah) — that line's missing room, so every results screen has its tiles in the same place (owner: "they
        /// use the SAME content").
        static let resultsLiftBase: CGFloat = 24
        private var finishLineRoom: CGFloat { (26 * airScale).rounded() + 22 }
        private var resultsTilesLift: CGFloat { Self.resultsLiftBase + (hasFinishLine ? 0 : finishLineRoom) }
        /// The results' button sits lower than the switches did (owner: "move the bottom buttons down a bit").
        private static let resultsButtonDrop: CGFloat = 14
        /// The well shows once its name row and a first line of text have room (lower, the text was cut off).
        private static let wellShowsAt: CGFloat = 100

        /// Room between the page's parts (owner: "enough room to breathe"): the full gap on a tall phone (his 6.7"),
        /// down to 60 % on a 6.1" one, so the zikr's text and notes still show there (owner: "even for the small phones").
        /// Set from the page's height, not shared out by the stack: flexible gaps shared the room with the space above
        /// the ring and ended up at their least everywhere.
        private func gap(_ height: CGFloat) -> some View {
            Color.clear.frame(height: (height * airScale).rounded())
        }

        /// 0.6 at a page 760 pt tall or less (a 6.1" phone's is ~778), 1 at 830 or more (a 6.7"'s is ~840).
        private var airScale: CGFloat { 0.6 + 0.4 * min(max((pageHeight - 760) / 70, 0), 1) }
        /// The switches' row: a 50 pt circle and its word.
        private static let switchHeight: CGFloat = 72

        /// A goal to finish: the sentence under the tiles (freestyle and Tasbih Fatimah have none).
        private var hasFinishLine: Bool { !sharedState.isDoingPostNamazZikr && sharedState.selectedMode != 0 }

        /// One quiet line, every word and number alike (owner: "make it all the same weight, color, size. and reduce
        /// the weight and size"): 13 pt light, in a soft sage — not the switches' grey, so it reads as its own thing
        /// under them (owner); full sage once the goal is passed.
        @ViewBuilder private var finishLine: some View {
            HStack(spacing: 6) {
                switch thirdTile {
                case .left(let left):
                    finishFlag
                    // The finish follows the clock while paused (it was the time the pause screen opened, stale by the
                    // pause's length): nothing is counted meanwhile, so what's left stays and the finish moves on.
                    TimelineView(.everyMinute) { now in
                        Text("\(String(inMinSecStyle2(from: left).dropFirst(3))) left · you'll finish around \(shortTime(now.date.addingTimeInterval(left)))")
                    }
                case .toGo(let n):
                    finishFlag
                    Text("\(n.formatted()) to go")
                case .counted:
                    // Past the goal and keeping going: said once, quietly.
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    Text("Goal reached · keeps going")
                }
            }
            .font(.system(size: 13, weight: .light))
            .foregroundStyle(goalReached ? Color.sage : Color.sage.opacity(0.75))
            .symbolRenderingMode(.monochrome)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }

        private var finishFlag: some View {
            Image(systemName: "flag.checkered")
                .font(.system(size: 12, weight: .light))
        }

        /// A small tile: its symbol, then the number big and the word under it.
        private func softStatTile<Content: View>(icon: String, @ViewBuilder lines: () -> Content) -> some View {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                lines()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: Self.statTileHeight)
            .background(ThemedRaised(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 6, offset: 3))
        }

        private func softStatLines(_ value: String, _ caption: String) -> some View {
            // The number and its word start at the same edge, the number where it stood (owner: the word takes the
            // number's lead, not the other way round).
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)
        }

        /// The tall tile: "rate", the pace big, per count / per tasbeeh, and how it compares with your usual.
        private func softRateTile(pace: (text: String, faster: Bool?)?,
                                  pacePerTasbeeh: (text: String, faster: Bool?)?) -> some View {
            VStack(spacing: 2) {
                Text("rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only the number moves (owner): the shown one slides up and out as the other comes in from below;
                // its caption and the pace line crossfade in place.
                // The top bar's flip (owner: "copy the same flip transition as in the top bar. Opacity and size change
                // too"): the Zikr title's 12 pt move and fade on its spring (CircleMotion.label), with the ⏸ / ‹ symbols'
                // shrink to 60 %. Reduce Motion: no move.
                // The outgoing number fades fast and the incoming one gently, so they barely overlap (owner: "maybe more
                // scale or more opacity"); the move and size keep the spring.
                ZStack {
                    rateValue(String(format: "%.2fs", shownPerCount))
                        .opacity(perCountOpacity)
                        .scaleEffect(showingPerTasbeeh ? 0.5 : 1)
                        .offset(y: showingPerTasbeeh ? -rateTravel : 0)
                    rateValue(shownPerTasbeeh)
                        .opacity(perTasbeehOpacity)
                        .scaleEffect(showingPerTasbeeh ? 1 : 0.5)
                        .offset(y: showingPerTasbeeh ? 0 : rateTravel)
                }
                ZStack {
                    Text("per count").opacity(showingPerTasbeeh ? 0 : 1)
                    Text("per tasbeeh").opacity(showingPerTasbeeh ? 1 : 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if pace != nil || pacePerTasbeeh != nil {
                    // Its own line, apart from the number and its caption (owner: "add a gap").
                    ZStack {
                        paceLine(pace).opacity(showingPerTasbeeh ? 0 : 1)
                        paceLine(pacePerTasbeeh).opacity(showingPerTasbeeh ? 1 : 0)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemedRaised(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), radius: 6, offset: 3))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(11)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }

        @Environment(\.accessibilityReduceMotion) private var rateReduceMotion
        /// How far the rate number moves as it flips: the Zikr title's 12 pt; none under Reduce Motion.
        private var rateTravel: CGFloat { rateReduceMotion ? 0 : 12 }

        /// The rate's number: a little smaller than it was (36), so the tile has room for the gap above the pace line.
        private func rateValue(_ value: String) -> some View {
            Text(value)
                .font(.system(size: 32, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }

        /// How this session compares with your usual pace: faster in sage, else secondary.
        @ViewBuilder private func paceLine(_ pace: (text: String, faster: Bool?)?) -> some View {
            if let pace {
                Text(pace.text)
                    .font(.system(size: 13, weight: pace.faster == true ? .medium : .regular, design: .rounded))
                    .foregroundStyle(pace.faster == true ? Color.sage : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }

        // MARK: mantra card

        private var mantraCard: some View {
            let title = sharedState.titleForSession
            return VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Button { showMantraPicker = true } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(title.isEmpty ? "choose a zikr" : title)
                                    .font(.system(size: 24, weight: .light, design: .rounded))
                                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                if !mantraLocked {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if isTaskSession {
                                Label(sharedState.selectedTask?.title ?? "your goal", systemImage: "target")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!mantraLocked)   // not .disabled: that grayed the name out
                    Spacer(minLength: 8)
                    if let mantra {
                        // The voice memo and photo, a tap away (owner, #17). No editing from the pause
                        // screen (owner, 2026-09-29): a zikr is edited on its own page.
                        ZikrMediaStrip(mantra: mantra, paused: paused, compact: true)
                    }
                }

                if let mantra {
                    let full = mantra.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let notes = mantra.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !full.isEmpty {
                        // Arabic lines in the Uthmani face, the rest (transliteration,
                        // meaning) in the app's light rounded type.
                        VStack(spacing: 6) {
                            ForEach(Array(full.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                let text = line.trimmingCharacters(in: .whitespaces)
                                if !text.isEmpty {
                                    let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
                                    Text(text)
                                        .font(arabic ? .custom("KFGQPCUthmanTahaNaskh", size: 26) : .system(size: 15, weight: .light, design: .rounded))
                                        .foregroundStyle(arabic ? .primary : .secondary)
                                        .lineSpacing(arabic ? 8 : 2)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }
                        .lineLimit(fullTextExpanded ? nil : 4)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: fullTextExpanded ? nil : 190, alignment: .top)
                        .clipped()
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.04)))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy) { fullTextExpanded.toggle() }
                        }
                    }
                    if !notes.isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                            BulletedNotes(text: notes)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.footnote)
                    }
                } else if title.isEmpty {
                    Text("its full text and notes show up here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
            .padding(16)
            .background(cardShape.fill(.ultraThinMaterial))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        }

        // MARK: controls

        private var controls: some View {
            VStack(spacing: 14) {
                // (The dimmer lives on the sleep page now — decision sleep-dimmer-place A.)
                // Tasbih Fatimah: no switches (owner: none of the settings chips).
                if !sharedState.isDoingPostNamazZikr {
                    chipsRow
                }
                // (Resume and Finish are in the top row now — decision top-bar-finish A.)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .animation(.snappy(duration: 0.25), value: toggleInactivityTimer)
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
                    .fullScreenCover(isPresented: Bindable(ui).showGoalIntro) {
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
                .fullScreenCover(isPresented: Bindable(ui).showSleepIntro) {
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
            .fullScreenCover(isPresented: Bindable(ui).showSetsPage) {
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
}

/// The pause screen's own state (`tasbeehView.pauseScreen_StatsSettingsBG`): one object for the screen's life, as its
/// @State were, so the screen redraws for exactly the properties its body reads (cleanup-map tangle 5, step 4). What
/// each one means is documented where the screen forwards it.
@MainActor @Observable final class PauseScreenState {
    var showSetsPage: Bool = false
    var setsPageTurnsOn: Bool = false
    var showSleepIntro: Bool = false
    var showGoalIntro: Bool = false
    var showHistory: Bool = false
    var wellRoom: CGFloat = 148
    var wellTextHeight: CGFloat = 0
    var cardEditing: ZikrCardRequest? = nil
    var bottomInset: CGFloat = 0
    var pageHeight: CGFloat = 900
    var showingPerTasbeeh: Bool = false
    var perCountOpacity: Double = 1
    var perTasbeehOpacity: Double = 0
    var showMantraPicker: Bool = false
    var chosenMantraName: String? = ""
    var chosenMantraObject: MantraModel? = nil
    var fullTextExpanded: Bool = false
    var scrollHeight: CGFloat = 0
}
