//
//  PagerChrome.swift
//  shukr
//
//  The chrome fixed over the pager — the top bar (☰, TopBar, the Zikr page's title), the chevron, the post-salah pill
//  on the page, the bottom bar — and the modifiers that make it follow the live scroll. Nested in PrayerTimesView as
//  before (an extension: same names, same code). Moved out of PrayerTimesAndTracker.swift (cleanup-map tangle 1, step 4).
//

import SwiftUI
import SwiftData
import WidgetKit

extension PrayerTimesView {
    /// Top bar (menu + TopBar on Salah, "Zikr" title on Zikr) and the chevron / bottom bar,
    /// fixed over the pager. Reads `live` so it alone re-renders while scrolling or dragging.
    struct PagerChromeView: View {
        @Environment(SharedStateClass.self) var sharedState
        var live: PagerLiveState
        @ObservedObject private var access = WhatsNewAccess.shared
        @Binding var showMapPage: Bool
        @Binding var showDailyAyahPage: Bool
        @Binding var showMantrasPage: Bool
        @Binding var showZikrHistory: Bool
        @Binding var showInsightsPage: Bool
        @Binding var showOldInsights: Bool
        @Binding var showNamesPage: Bool
        @Binding var showTasbeehPage: Bool

        @State private var showMenu = false
        @State private var pendingMenuAction: (() -> Void)? = nil
        /// "What's new" (tap the build line in the menu; DEBUG / TestFlight only).
        @State private var showWhatsNew = false
        /// The compass calibration sheet (the line under the circle, or ☰ → Calibrate compass).
        @State private var showCalibration = false
        @Environment(PrayerViewModel.self) private var viewModel
        #if DEBUG
        @State private var demoViewer = false
        @State private var demoAlarmCheck = false
        @State private var demoRingDepth = false
        @State private var demoRaisedList = false
        @State private var demoListSandbox = false
        @State private var demoLATuner = false
        @State private var demoPileMock: String?
        @State private var demoLiveActivityStep = false
        struct MockVariant: Identifiable { let id: String }
        #endif
        /// The pill's camera is open for this prayer (PrayerPhotos.swift).
        @State private var prayerPhoto: PrayerPhotoTarget?
        /// The pill's prayer, marked and still in its window: its camera section (owner: photos "any time in that window so
        /// long as its marked").
        private var pillPhotoTarget: PrayerPhotoTarget? {
            #if DEBUG
            // `-demoPostSalahOffer -demoPillPhoto`: the pill's camera without a marked prayer (the simulator's walk).
            if let name = live.postSalahNudge, ProcessInfo.processInfo.arguments.contains("-demoPillPhoto") {
                return PrayerPhotoTarget(key: PrayerPhotos.key(dayKey: PrayerDay.key(), name: name), title: "\(name) · 4:52 PM")
            }
            #endif
            let _ = PrayerPhotoRevision.shared.value   // re-read when a photo is added from the row's editor
            guard let name = live.postSalahNudge,
                  let row = viewModel.todaysPrayers.first(where: { ($0.name == name || $0.displayName == name) && $0.isCompleted }),
                  Date() < row.endTime,
                  // Already has its photo (taken from the row's hold editor): no camera in the pill (owner).
                  !PrayerPhotos.exists(for: row) else { return nil }
            return PrayerPhotoTarget.forMarked(row)
        }

        /// The post-salah Tasbih Fatimah, from the pill or a marked row's button (G).
        private func openPostSalahTasbih() {
            sharedState.isDoingPostNamazZikr = true
            // In place (decision post-salah-entry A): the cover with no animation of its own, the session
            // fading in over the Salah page — list open or closed, nothing measured. The sheet is left as it is.
            // Refused (another session's cover still closing — Frank's review): the usual sheet, never a cover
            // with neither a slide nor a fade.
            if SessionHandoff.shared.openInPlace() {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { showTasbeehPage = true }
            } else {
                showTasbeehPage = true
            }
        }

        /// One row of the hamburger popover; closes it and runs `action` after it's gone.
        /// `dot`: a badge on the row's symbol, the one ☰ carries for it (owner: say what ☰'s dot is for).
        private func menuRow(_ title: String, _ symbol: String, dot: Color? = nil, action: @escaping () -> Void) -> some View {
            Button {
                pendingMenuAction = action
                showMenu = false
            } label: {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol)
                        .overlay(alignment: .topTrailing) {
                            if let dot { Circle().fill(dot).frame(width: 7, height: 7).offset(x: 2, y: -2) }
                        }
                }
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        private var showBottom: Bool { sharedState.navPosition == .bottom }
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// How far a top-bar title travels as the pager moves between Salah and Zikr.
        static let titlePush: CGFloat = 150
        /// What follows the live scroll does it in `ChromeFollow` / `ChromeLeaves`: this body reads none of it, so it
        /// isn't re-run on every frame of a swipe (audit D, finding 7).
        private func follow(_ role: ChromeFollow.Role) -> ChromeFollow {
            ChromeFollow(live: live, role: role, sheetFollows: sheetFollows)
        }
        @AppStorage(SalahSheetDrag.key) private var sheetFollows = SalahSheetDrag.defaultOn

        var body: some View {
            let _ = viewModel.revision   // redraw after marks / edits, as on objectWillChange (step 8)
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // The two titles push each other with the pager (owner, 2026-10-01): swiping to Zikr
                    // (the page on the left) brings "Zikr" in from the left and pushes the Salah title
                    // out to the right, following the finger; back again the other way. Only these
                    // offsets read the live scroll — the titles' own bodies don't.
                    ZStack(alignment: .top) {
                        TopBar()
                            #if DEBUG
                            .modifier(DemoTip(tip: SwipeToZikrTip(), on: TourHintDemo.tip == "zikr", edge: .top))
                            #endif
                            .modifier(follow(.salah(push: Self.titlePush)))
                        ZikrPageTitle()
                            .modifier(follow(.zikr(push: Self.titlePush)))
                    }

                    // Menu button: a native Menu instead of the hand-rolled drawer, which
                    // toggled shared state and re-rendered the whole home screen to animate.
                    HStack {
                        // The menu is a popover (a native Menu can't show the wordmark):
                        // "shukr" on top like the old sidebar, then the destinations.
                        ZStack {
                        // Zikr page, top left: History (the Zikr tab reorganisation; symbols only, 2026-10-01).
                        ZikrDoor(title: "History", symbol: "clock.arrow.circlepath") { showZikrHistory = true }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("historyDoor", $0) }
                            .modifier(follow(.zikr(push: 0)))
                            // Locked with the page (ZikrLock): faint and shut.
                            .opacity(ZikrLock.shared.locked ? 0 : 1)
                            .allowsHitTesting(!ZikrLock.shared.locked)

                        Button { showMenu = true } label: {
                            Image(systemName: "line.3.horizontal")
                                .background(.white.opacity(0.01))
                                .frame(width: 24, height: 24)
                                .font(.system(size: 20))
                                .fontWeight(.light)
                                .fontDesign(.rounded)
                                .foregroundColor(.gray.opacity(0.8))
                                // The compass needs calibrating: a red dot (its own small view, so the
                                // chrome doesn't redraw with the compass).
                                // The tour not yet taken to its end: a green dot (Tour.swift), under the compass's.
                                .overlay(alignment: .topTrailing) {
                                    // Excused (Excused.swift): its own dot, under the tour's and the compass's.
                                    ZStack { ExcusedMenuBadge(); TourMenuBadge(); CompassMenuBadge() }.offset(x: 3, y: -1)
                                }
                                .padding()
                        }
                        .popover(isPresented: $showMenu, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("shukr")
                                    .font(.largeTitle)
                                    .fontWeight(.thin)
                                    .fontDesign(.rounded)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 18)
                                    .padding(.bottom, 10)
                                Divider()
                                // Journey (Journey.swift): Insights and Moments in one place (owner, 2026-10-15); Moments is
                                // its tile.
                                menuRow("Journey", "point.bottomleft.forward.to.point.topright.scurvepath") { JourneyPresenter.shared.open = true }
                                menuRow("Daily Ayah", "book") { showDailyAyahPage = true }
                                menuRow("99 Names", "moon.stars") { showNamesPage = true }
                                // While excused only (owner): quick to manage or end (Excused.swift).
                                if CircleStage.shared.excused != nil {
                                    menuRow("Excused Mode", "pause.circle", dot: ExcusedMenuBadge.ink) { NotificationCenter.default.post(name: Excused.openSheet, object: nil) }
                                }
                                CompassMenuRow {
                                    pendingMenuAction = { showCalibration = true }
                                    showMenu = false
                                }
                                // Until the tour is taken to its end (Tour.swift).
                                TourMenuRow {
                                    pendingMenuAction = { NotificationCenter.default.post(name: TourRuntime.start, object: nil) }
                                    showMenu = false
                                }
                                // (No "Zikr Tour" row any more: the Zikr page's lock is its way in — owner, 2026-10-08.)
                                // Which build this is (BuildInfo): when it was built + the commit.
                                // Tap → What's new (DEBUG / TestFlight).
                                BuildLineButton {
                                    pendingMenuAction = { showWhatsNew = true }
                                    showMenu = false
                                }
                                    .font(.caption2)
                                    .fontDesign(.rounded)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                            }
                            .padding(.bottom, 8)
                            .frame(width: 250)
                            .presentationCompactAdaptation(.popover)
                            .stageCover("menu")
                        }
                        // A pull down on the Salah page opens it (SalahSheetDrag.openMenu).
                        .onReceive(NotificationCenter.default.publisher(for: SalahSheetDrag.openMenu)) { _ in
                            showMenu = true
                        }
                        .onChange(of: showMenu) { _, open in
                            SalahSheetDrag.menuChanged(open: open, byRow: pendingMenuAction != nil)
                            // The chosen row runs once the popover has faded (its push isn't attempted while the
                            // presentation is still going). Not at its onDisappear: that comes ~0.4 s after it's gone
                            // from the screen, and the row felt slow (sim, tr-pager).
                            guard !open, let action = pendingMenuAction else { return }
                            pendingMenuAction = nil
                            Task {
                                try? await Task.sleep(for: .seconds(CircleMotion.popoverAwayDuration))
                                action()
                            }
                        }
                        .sheet(isPresented: $showWhatsNew) { WhatsNewView().stageCover("whatsNew") }
                        .fullScreenCover(isPresented: $showCalibration) {
                            CompassCalibrationSheet().stageCover("compassCalibration")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: CompassHealth.openSheet)) { _ in
                            showCalibration = true
                        }
                        #if DEBUG
                        .task {   // `-demoCalibrationSheet` / `-demoMenuOpen`: the sheet / ☰ menu a few s in (screenshots)
                            let args = ProcessInfo.processInfo.arguments
                            if args.contains("-demoMenuOpen") {
                                try? await Task.sleep(for: .seconds(6))
                                showMenu = true
                            }
                            guard args.contains("-demoCalibrationSheet") else { return }
                            try? await Task.sleep(for: .seconds(4))
                            showCalibration = true
                        }
                        #endif
                        .modifier(follow(.salah(push: 0)))
                        }
                        Spacer()
                        ZStack(alignment: .trailing) {
                        // Zikr page, top right: nothing (owner, 2026-10-15: the books door went — "N of M daily goals
                        // done" under the wheel opens Your azkar).
                        // Salah page, top right, owner only: the look prototype's switcher (SalahLook.swift).
                        // (Settings is the right page again — its gear here went, owner 2026-10-19.)
                        if access.available && !TourRuntime.shared.active {
                            HStack(spacing: 0) {
                                SalahPlayButton()
                                SalahLookSwitcher()
                            }
                            .padding(.trailing, 8)
                            .modifier(follow(.salah(push: 0)))
                        }
                        }
                    }
                }

                Spacer()

                ZStack(alignment: .bottom) {
                    // Chevron hint: Salah page, sheet closed. Follows the pull-to-refresh nudge.
                    Button {
                        sharedState.navPosition = showBottom ? .main : .bottom   // the page and the chrome animate it
                    } label: {
                        ChevronHint(live: live)
                    }
                    .modifier(follow(.chevron(sheetOpen: showBottom)))

                    // Bottom bar: Salah with the sheet up, and always on Zikr. Above it, the soft looks' "N done"
                    // (SoftDoneFooter): a fixed spot, fading with the bar on Salah, not moving with the card.
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            SoftDoneFooter()
                            MemoriesFooterLink()   // the day's page: all five marked, so no "N done" there
                        }
                        .animation(.easeOut(duration: CircleMotion.quick), value: DayPageState.shared.up)
                        .modifier(follow(.doneFooter(sheetOpen: showBottom)))
                        CustomBottomBar()
                            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { y in
                                if abs((DayPageState.shared.salahBarTop ?? -1) - y) > 0.5 { DayPageState.shared.salahBarTop = y }
                            }
                            .modifier(follow(.bottomBar(sheetOpen: showBottom)))
                    }
                }
            }
            // Just prayed: the post-salah pill, always under the top bar — the same spot with the prayer
            // list open or closed, so it never travels across the page (owner, decision
            // post-salah-pill-place C). Chrome, above the pager: dragging it never moves a page.
            .overlay(alignment: .top) {
                if live.postSalahNudge != nil {
                    PostSalahNudgeOnPage(live: live, onPhoto: pillPhotoTarget.map { target in
                        { live.postSalahNudge = nil; prayerPhoto = target }
                    }) {
                        // The tour's pill came from a practice mark: it never opens a real, saved session (audit A1);
                        // ✕ closes it.
                        guard !TourRuntime.shared.active else { return }
                        live.postSalahNudge = nil
                        openPostSalahTasbih()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .id(live.postSalahNudge)   // a new mark: a new pill, its 15 s from the start (audit A)
                }
            }
            // G · the marked row's buttons (PrayerRowActions): its camera and Tasbih open as the pill's would; the list
            // closing with the buttons up hands the moment to the pill.
            .onReceive(NotificationCenter.default.publisher(for: PrayerRowActions.openTasbih)) { _ in
                PrayerRowActions.shared.name = nil
                openPostSalahTasbih()
            }
            .onReceive(NotificationCenter.default.publisher(for: PrayerRowActions.openCamera)) { note in
                guard let name = note.object as? String,
                      let row = viewModel.todaysPrayers.first(where: { $0.name == name && $0.isCompleted }) else { return }
                PrayerRowActions.shared.name = nil
                prayerPhoto = PrayerPhotoTarget.forMarked(row)
            }
            .onChange(of: sharedState.navPosition) { _, position in
                guard position == .main, let name = PrayerRowActions.shared.name else { return }
                PrayerRowActions.shared.name = nil
                if !TourRuntime.shared.active { live.postSalahNudge = name }
            }
            // A Live Activity's Photo: the same camera as the pill's, for that prayer.
            .onReceive(NotificationCenter.default.publisher(for: PrayerLiveActivities.openPhoto)) { note in
                guard let name = note.object as? String,
                      let row = viewModel.todaysPrayers.first(where: { $0.name == name && $0.isCompleted }),
                      let target = PrayerPhotoTarget.forMarked(row) else { return }
                prayerPhoto = target
            }
            
            // The pill's camera: a photo of the prayer just marked (PrayerPhotos.swift).
            .fullScreenCover(item: $prayerPhoto) { target in
                PrayerPhotoCapture(target: target) { prayerPhoto = nil }
            }
            #if DEBUG
            // `-demoPhotoViewer`: the newest saved prayer photo, full screen (the simulator's look at the viewer).
            .fullScreenCover(isPresented: $demoViewer) {
                if let key = PrayerPhotos.newestKey {
                    PrayerPhotoViewer(key: key) { demoViewer = false }.presentationBackground(.clear)
                }
            }
            .task {
                // `-demoMemories`: three weeks of stand-in photos; `-demoMemoriesOpen`: then Memories opens.
                if ProcessInfo.processInfo.arguments.contains("-demoMemories") { await PrayerPhotos.seedDemo() }
                if ProcessInfo.processInfo.arguments.contains("-heicSelfTest") { await PrayerPhotos.heicSelfTest() }
                if ProcessInfo.processInfo.arguments.contains("-demoMemoriesOpen") {
                    try? await Task.sleep(for: .seconds(2))
                    MemoriesPresenter.shared.open = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demoPhotoViewer") {
                    try? await Task.sleep(for: .seconds(2))
                    demoViewer = PrayerPhotos.newestKey != nil
                }
                if ProcessInfo.processInfo.arguments.contains("-demoListSandbox") {   // ListDragSandbox.swift
                    try? await Task.sleep(for: .seconds(2))
                    demoListSandbox = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demoRaisedListMock") {   // PrayerListRaisedMock.swift
                    try? await Task.sleep(for: .seconds(2))
                    demoRaisedList = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demoRingDepth") {   // RingDepthMocks.swift
                    try? await Task.sleep(for: .seconds(2))
                    demoRingDepth = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demoAlarmCheck") {
                    try? await Task.sleep(for: .seconds(2))
                    demoAlarmCheck = true
                }
                if ProcessInfo.processInfo.arguments.contains("-laTuner") {
                    try? await Task.sleep(for: .seconds(2))
                    demoLATuner = true
                }
                if ProcessInfo.processInfo.arguments.contains("-demoLiveActivityStep") {
                    try? await Task.sleep(for: .seconds(2))
                    demoLiveActivityStep = true
                }
                if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-demoPileMock"),
                   i + 1 < ProcessInfo.processInfo.arguments.count {
                    try? await Task.sleep(for: .seconds(2))
                    demoPileMock = ProcessInfo.processInfo.arguments[i + 1]
                }
            }
            // `-demoPileMock A|B|C|D`: the open pile v2 mock-ups (PrayerMemories.swift).
            .fullScreenCover(item: Binding(get: { demoPileMock.map { MockVariant(id: $0) } }, set: { demoPileMock = $0?.id })) { v in
                MemoriesPileMock(variant: v.id)
            }
            // `-demoLiveActivityStep`: the Live Activity setup page, not in the setup yet (LiveActivitySetupStep.swift).
            #if DEBUG
            .fullScreenCover(isPresented: $demoLiveActivityStep) { LiveActivitySetupPreview() }
            #endif
            // `-demoAlarmCheck`: Settings' Alarm check page (FajrAlarmKit.swift).
            .sheet(isPresented: $demoAlarmCheck) { NavigationStack { FajrAlarmCheckView() } }
            .sheet(isPresented: $demoRingDepth) { NavigationStack { RingDepthMockPage() } }
            .sheet(isPresented: $demoRaisedList) { NavigationStack { RaisedListMockPage() } }
            .fullScreenCover(isPresented: $demoListSandbox) { ListDragSandbox() }
            // `-laTuner`: Settings → Live Activities → Tune the card's look.
            .sheet(isPresented: $demoLATuner) { LATunerView() }
            #endif
            // The sheet popping (whoever changed it): the chevron, "N done" and the bar fade with the page's own move.
            .animation(CircleMotion.movement(CircleMotion.page, reduced: reduceMotion), value: showBottom)
            // The pill comes and goes the same way whoever sets it (rule 6); a flick and the timer fade it themselves
            // first, then remove it with no animation.
            .animation(CircleMotion.movement(.easeInOut(duration: CircleMotion.pillDuration), reduced: reduceMotion),
                       value: live.postSalahNudge)
            .ignoresSafeArea(edges: .bottom)
            .modifier(ChromeLeaves(live: live))
            // The opening on the Salah circle (circle step 4): the chrome waits, then fades in as the ring lands.
            .opacity(CircleStage.shared.pageHidden ? 0 : 1)
            .animation(CircleMotion.ease(CircleMotion.pageRevealDuration), value: CircleStage.shared.pageHidden)
        }
    }

    /// A piece of the chrome following the live scroll: its fade, its push and whether it takes taps. Only this
    /// re-renders per frame of a swipe (audit D, finding 7).
    struct ChromeFollow: ViewModifier {
        enum Role {
            /// The Salah page's chrome: gone toward Zikr, pushed right by `push`.
            case salah(push: CGFloat)
            /// The Zikr page's chrome: in from the left by `push`.
            case zikr(push: CGFloat)
            /// The chevron: Salah with the sheet closed.
            case chevron(sheetOpen: Bool)
            /// The soft looks' "N done": Salah with the sheet open.
            case doneFooter(sheetOpen: Bool)
            /// The bottom bar: Salah with the sheet open, and always on Zikr.
            case bottomBar(sheetOpen: Bool)
        }
        let live: PagerLiveState
        let role: Role
        /// The Salah sheet follows the finger (SalahSheetDrag): the sheet's pieces follow its live progress instead of
        /// its resting state.
        var sheetFollows = false

        /// How open the sheet is, 0...1: live when it follows the finger, else the resting state.
        private func sheet(_ open: Bool) -> CGFloat { sheetFollows ? live.sheetProgress : (open ? 1 : 0) }

        func body(content: Content) -> some View {
            /// How far onto the Zikr page we are, 0...1, live from the scroll offset.
            let zikr = min(max(1 - live.scrollProgress, 0), 1)
            let (opacity, push, taps): (CGFloat, CGFloat, Bool) = switch role {
            case .salah(let push): (1 - zikr, zikr * push, zikr < 0.5)
            case .zikr(let push): (zikr, -(1 - zikr) * push, zikr > 0.5)
            case .chevron(let open): ((1 - sheet(open)) * (1 - zikr), 0, sheet(open) < 0.5 && zikr < 0.5)
            case .doneFooter(let open): (sheet(open) * (1 - zikr), 0, sheet(open) >= 0.5 && zikr < 0.5)
            case .bottomBar(let open): (max(sheet(open), zikr), 0, sheet(open) >= 0.5 || zikr > 0.5)
            }
            // "N done" rides up under the list while a finger brings the sheet (its fixed spot is the open rest).
            let rise: CGFloat = if case .doneFooter = role, sheetFollows {
                (1 - live.sheetProgress) * live.sheetRun
            } else { 0 }
            content
                .offset(x: push, y: rise)
                .opacity(Double(opacity))
                .allowsHitTesting(taps)
        }
    }

    /// Toward Settings the chrome fades out in place with the anchored Salah page (SalahPageAnchor: gone by `goneAt`), so
    /// nothing shifts sideways, as toward Zikr (owner, 2026-10-19: "swiping left right doesn't feel even. cuz of top bar and
    /// bottom bar … it shifts when we pull in the settings page instead of mimicking how it does when we pull in zikr").
    /// It used to leave WITH the Salah page at full speed (2026-09-25). No taps past halfway.
    private struct ChromeLeaves: ViewModifier {
        let live: PagerLiveState
        func body(content: Content) -> some View {
            let settings = min(max(live.scrollProgress - 1, 0), 1)
            content
                .allowsHitTesting(settings < 0.5)
                .opacity(Double(max(0, 1 - settings / SalahPageAnchor.goneAt)))
        }
    }

    /// The chevron hint, nudged by the pull-down drag; while the closed page is pulled down it gives way to a small quiet
    /// line, "Keep pulling for the menu", then "Let go for the menu" (the pull opens ☰ now — owner; it used to refresh).
    private struct ChevronHint: View {
        let live: PagerLiveState
        var body: some View {
            let pulling = live.refreshReach > 0.15
            Image(systemName: "chevron.up")
                .font(.title3)
                .foregroundStyle(TourHints.shared.chevronLine != nil ? Color.secondary
                                 : live.pull != 0 ? Color.secondary : Color(.secondarySystemFill))
                // The tour's words just above the chevron (Tour.swift).
                .overlay(alignment: .bottom) {
                    if let line = TourHints.shared.chevronLine {
                        Text(line).font(.footnote).fontDesign(.rounded).fontWeight(.light)
                            .foregroundStyle(Color(.secondaryLabel)).fixedSize()
                            .offset(y: -30)
                    }
                }
                // The tour's "Swipe up" step points at it.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("chevron", $0) }
                .opacity(pulling ? 0 : 1)
                // An overlay, so the chevron's place is exactly as it was.
                .overlay {
                    Text(live.refreshReach >= 1 ? "Let go for the menu" : "Keep pulling for the menu")
                        .font(.footnote).fontDesign(.rounded).fontWeight(.light)
                        .foregroundStyle(Color(.tertiaryLabel))   // explicit: in the Button's label .tertiary took the tint
                        .fixedSize()
                        .contentTransition(.opacity)
                        .opacity(pulling ? 1 : 0)
                }
            .animation(.easeOut(duration: CircleMotion.quick), value: pulling)
            .animation(.easeOut(duration: CircleMotion.quick), value: live.refreshReach >= 1)
            .padding(.bottom, 30)
            .padding()
            .offset(y: live.pull)
        }
    }

    /// The post-salah pill under the top bar, on the Salah page only.
    private struct PostSalahNudgeOnPage: View {
        let live: PagerLiveState
        var onPhoto: (() -> Void)? = nil
        let onOpen: () -> Void
        var body: some View {
            let zikr = min(max(1 - live.scrollProgress, 0), 1)
            let settings = min(max(live.scrollProgress - 1, 0), 1)
            PostSalahNudge(onOpen: { TourRuntime.shared.event(.pillOpened); onOpen() },
                           onDismiss: {
                               live.postSalahNudge = nil   // the pill animates (or not) itself
                               TourRuntime.shared.event(.pillClosed)   // ✕ or a flick: the tour's to-do (never its expiry)
                           },
                           onPhoto: TourRuntime.shared.active ? nil : onPhoto,
                           shown: zikr < 0.5 && settings < 0.5)
                // The tour's post-salah step points at it, and ends when it goes (Tour.swift).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("pill", $0) }
                .onAppear { TourRuntime.shared.pillVisible = true }
                .onDisappear { TourRuntime.shared.pillVisible = false }
                .padding(.top, 64)
                .opacity(Double(1 - zikr))
                .allowsHitTesting(zikr < 0.5)
        }
    }

    /// The Zikr page's title in the fixed top bar, in TopBar's type (owner, 2026-10-01). It follows the
    /// wheel: a centred task shows its streak ("8 Day Streak", "0 Day Streak" when there's none yet);
    /// freestyle and New task show "Zikr". Each item's label is pushed in the wheel's direction — moving
    /// down, the next one comes up from below and the last goes up and out; moving up, the other way.
    /// A tap on a task's streak toggles "Best N Days" (back to the streak on the next tap or item).
    /// Outline beads; the flame is an outline in grey until today's goal is met, then filled sage.
    struct ZikrPageTitle: View {
        @Query private var tasks: [TaskModel]
        @State private var showBest = false
        private let focus = ZikrWheelFocus.shared
        private static let travel: CGFloat = 12
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            // The tour's example tasks too (TourExamples): their streaks show like any task's.
            let task = focus.taskID.flatMap { id in (TourExamples.shared.tasks ?? tasks).first { $0.id == id } }
            let down = focus.movedDown
            // Same metrics as TopBar's location row so the title sits where the city does.
            ZStack {
                // Reduce Motion: the labels fade in place.
                let travel = reduceMotion ? 0 : Self.travel
                label(task)
                    .id(focus.key)
                    .transition(.asymmetric(
                        insertion: .offset(y: down ? travel : -travel).combined(with: .opacity),
                        removal: .offset(y: down ? -travel : travel).combined(with: .opacity)))
            }
            .padding()
            .frame(height: 24, alignment: .center)
            .font(.caption)
            .fontDesign(.rounded)
            .fontWeight(.thin)
            .animation(CircleMotion.label, value: focus.key)
            .onChange(of: focus.key) { _, _ in showBest = false }
            .padding()
        }

        @ViewBuilder private func label(_ task: TaskModel?) -> some View {
            if let task {
                let streak = task.streak()
                HStack(alignment: .center) {
                    Image(systemName: streak.keptToday && streak.current > 0 ? "flame.fill" : "flame")
                        .foregroundColor(streak.keptToday && streak.current > 0 ? Color.sage : .secondary)
                    Group {
                        // "0 day streak", a tap "Best streak: N days" (owner, 2026-10-15: not "Goal streak").
                        if showBest {
                            Text("Best streak: \(streak.best) day\(streak.best == 1 ? "" : "s")").transition(.blurReplace)
                        } else {
                            Text("\(streak.current) day streak").transition(.blurReplace)
                        }
                    }
                    .fixedSize()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    triggerSomeVibration(type: .light)
                    withAnimation { showBest.toggle() }
                }
            } else {
                HStack {
                    Image(systemName: "circle.hexagonpath")
                        .foregroundColor(.secondary)
                    Text("Zikr")
                }
            }
        }
    }
    /// The Salah sheet's list (the old Salah | Zikr tab under the circle is gone: the Zikr page has its own wheel).
    struct BottomSharedView: View {
        @Binding var showDailyAyahView: Bool

        var body: some View {
            VStack {
                TodaysPrayerListView(showDailyAyahView: $showDailyAyahView)
                    // The card is a fixed width: at the accessibility text sizes a name filled a row, its time wrapped
                    // a character a line or was cut to "7:…", "3 done" broke in two (Frank's largest-text pass). The
                    // list stops growing at the largest standard size, as the circle's words do.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .modifier(SalahLookListFrame())   // the look prototype; today's = 260 pt in FlatBorder
            }
        }
    }

    
    struct CustomBottomBar: View {
        @Environment(SharedStateClass.self) var sharedState
        @Environment(\.circleTheme) private var theme

        var body: some View {
            VStack(spacing: 0){

                    // One surface on every page: the bar wears the theme. It fades out toward Settings (ChromeLeaves;
                    // it used to leave with the Salah page), so a Settings look only ever showed mid-swipe — the bar turned white at the page's
                    // midpoint (bottom-bar-colour, owner: "looks careless").
                    ThemedBarDivider()

                    
                    HStack {
                        
                        
                        Button(action: {
                            sharedState.horizontalPage = .zikr
                        }) {
                            VStack(spacing: 6){
                                Image(systemName: "circle.hexagonpath")
                                    .font(.system(size: 20))
                                    // Still locked (ZikrLock): the green dot — something to do here (owner).
                                    .overlay(alignment: .topTrailing) {
                                        Circle()
                                            .fill(TourInk.green)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 4, y: -2)
                                            .opacity(ZikrLock.shared.locked ? 1 : 0)
                                            .animation(.easeInOut(duration: 0.3), value: ZikrLock.shared.locked)
                                            .accessibilityHidden(true)
                                    }
                                Text("Zikr")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor( sharedState.horizontalPage == .zikr ? .green : .gray)
                            .frame(width: 100)
                        }

                        Spacer()
                        
                        Button(action: {
                            sharedState.horizontalPage = .main   // the pager scrolls itself, like its siblings
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait")
                                    .font(.system(size: 20))
                                Text("Salah")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor(sharedState.horizontalPage == .main ? .green : .gray) // by page, like its siblings
                            .frame(width: 100)
                        }
                        
                        Spacer()

                        // Settings, the right page (back, owner 2026-10-19; it was Journey 2026-10-17 → 19).
                        Button(action: {
                            sharedState.horizontalPage = .settings
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "gear")
                                    .font(.system(size: 20))
                                Text("Settings")
                                    .font(.system(size: 12))
                                    .fontWeight(.light)
                                    .fontDesign(.rounded)
                            }
                            .foregroundColor(sharedState.horizontalPage == .settings ? .green : .gray)
                            .frame(width: 100)
                            // The tour's last step taps this (audit J: the bar is taught as well as the swipe).
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { TourTargets.shared.set("settingsTab", $0) }
                        }
                    }
                    .padding(.top, 15)
                    .padding(.bottom, 25)
                    .padding(.horizontal, 45)
                    .opacity(0.8)
//                    .background(Color("bgColor"))
                
            }
            .background(theme.backdrop)
        }
        
    }
}
