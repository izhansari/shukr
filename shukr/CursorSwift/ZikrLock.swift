//
//  ZikrLock.swift
//  shukr
//
//  The Zikr tab is locked until its tour is done (owner, 2026-10-08: "lock the Zikr page and put like a frosted material
//  over it, and it says … that it's locked and you can unlock it, so that way it seems more fun to do … they have to do
//  the tour before they can access anything in the Zikr tab"). The page stays where it is under frosted glass, with a
//  card that unlocks it by starting the Zikr Tour; finishing the tour unlocks it for good. While the app tour or the
//  Zikr Tour runs, the page is theirs (the tours guard it themselves). Every way into Zikr from outside — widgets,
//  controls, Shortcuts, reminders, a zikr's page — lands on this card instead while it's locked.
//

import SwiftUI
import SwiftData

@MainActor @Observable final class ZikrLock {
    static let shared = ZikrLock()

    /// The Zikr Tour has been taken to its end (its own key, so an earlier finish counts), or Zikr was already theirs
    /// when the lock arrived (decision zikr-lock-existing B).
    private(set) var unlocked = UserDefaults.standard.bool(forKey: ZikrTour.completedKey)
        || UserDefaults.standard.bool(forKey: ZikrLock.alreadyUsedKey)

    /// Had Zikr history (tasks or sessions) the first time this version ran: never locked.
    static let alreadyUsedKey = "zikrLock.alreadyUsed"
    /// That first look has been taken (once per install).
    static let checkedKey = "zikrLock.checkedExisting"

    /// Once, the first time the app runs with the lock (owner, decision zikr-lock-existing B: "only new people"): anyone
    /// with a task or a session already keeps Zikr open. A new install has neither, so it starts locked.
    func checkExisting(in context: ModelContext) {
        let d = UserDefaults.standard
        guard !d.bool(forKey: Self.checkedKey) else { return }
        d.set(true, forKey: Self.checkedKey)
        let tasks = (try? context.fetchCount(FetchDescriptor<TaskModel>())) ?? 0
        let sessions = (try? context.fetchCount(FetchDescriptor<SessionDataModel>())) ?? 0
        guard tasks + sessions > 0 else { return }
        d.set(true, forKey: Self.alreadyUsedKey)
        unlocked = true
    }

    /// Settings' test switch (dev builds, owner: "i wanna be able to test in my dev build"): locked as a new person
    /// would see it (the tour not taken), or open.
    func setLockedForTesting(_ on: Bool) {
        let d = UserDefaults.standard
        if on {
            d.set(false, forKey: ZikrTour.completedKey)
            d.set(false, forKey: ZikrTour.offeredKey)
            d.set(false, forKey: Self.alreadyUsedKey)
            unlocked = false
        } else {
            d.set(true, forKey: Self.alreadyUsedKey)
            unlocked = true
        }
    }

    /// Locked now: not unlocked, and no tour is running on the page.
    var locked: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-zikrUnlocked") { return false }
        #endif
        return !unlocked && !ZikrTour.shared.active && !TourRuntime.shared.active
    }

    /// The Zikr Tour reached its end.
    func unlock() {
        guard !unlocked else { return }
        unlocked = true
        justUnlocked += 1
    }
    /// Bumped once on unlocking (the page's little moment).
    private(set) var justUnlocked = 0

    /// The narration is up (page 2): the top bar and the tab bar step away and the pager holds still — the Zikr page is
    /// the whole app for that moment (owner: "make that the whole focus … so that we know that we've entered the tour").
    var focus = false

    #if DEBUG
    /// `-zikrLocked`: locked again at launch, as a new person sees it (the simulator's walk).
    private init() {
        if ProcessInfo.processInfo.arguments.contains("-zikrLocked") { setLockedForTesting(true) }
    }
    #endif
}

/// The locked Zikr page (owner, 2026-10-08; decisions zikr-lock-quote A, zikr-lock-flow A — board/mocks/zikr-lock-quote).
/// The wheel under it is blurred (ZikrPageView) under a wash of the page's own colour. One view, two pages:
/// - Page 1 builds itself up on each arrival: the verse alone in the middle, then it rises to its place, then "What's
///   inside" (three items, one after another), then "Unlock now" (a tap arms it, a second confirms).
/// - Page 2 grows in place on the second tap — no sheet, no new page: the verse stays where it is; what's inside and
///   Unlock now fade away, the top bar and tab bar step away (`ZikrLock.focus`), the page goes plain, and the narration
///   (Sahih al-Bukhari 7405) comes in a line at a time, then Begin → the Zikr Tour. ✕ goes back to page 1.
/// Light or dark is the app's own look, never changed here (owner).
struct ZikrLockCover: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SharedStateClass.self) private var sharedState
    @Environment(\.circleTheme) private var theme
    @State private var lock = ZikrLock.shared

    /// Page 1's build: 0 nothing · 1 the verse in the middle · 2 the verse at its place · 3 + what's inside · 4 + Unlock.
    @State private var stage = 0
    /// What's inside's items shown (one after another).
    @State private var itemsShown = 0
    /// Page 2's parts shown: 1 the heading, 2…5 the narration's lines, 6 the source, 7 the bridge to shukr, 8 Begin.
    @State private var linesShown = 0
    /// The quote's lines wiped in so far, left to right, one at a time (each narration part is two lines).
    @State private var quoteShown = 0
    /// Begin was tapped: everything fades away before the tour comes in.
    @State private var leaving = false
    /// Page 3: the first zikr, its task already made (owner: "show it as a task ring … that they then click on to start
    /// the counter"), with its meaning and a listen before they start.
    @State private var third = false
    /// Its parts shown: 1 the heading and the ring, 2 the name and its meaning, 3 the source and Listen, 4 the prompt.
    @State private var thirdShown = 0
    @State private var firstTask: TaskModel?
    @State private var audio = ZikrAudio()
    @State private var breathe = false
    @State private var armed = false
    @State private var token = 0
    @State private var armedWidth: CGFloat = 0
    @State private var restWidth: CGFloat = 0
    @State private var verseHeight: CGFloat = 0
    /// Page 1's content under the verse (what's inside, Unlock now), laid out from the start.
    @State private var pageOneHeight: CGFloat = 0
    /// Page 2's content under the verse (the narration, the bridge), laid out from the start too, so the verse can glide
    /// to page 2's centred place as it opens.
    @State private var pageTwoHeight: CGFloat = 0
    /// Begin's room at the bottom (page 2's stack is centred in what's left).
    private static let beginRoom: CGFloat = 68
    @State private var run: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            // Each page's whole stack centred on the page (owner: "the whole stack is centered vertically"); the verse
            // glides from page 1's place to page 2's as it opens (owner: "we can move the verse up if we need to").
            let pageOneTop = max(24, (geo.size.height - verseHeight - pageOneHeight) / 2)
            let pageTwoTop = max(24, (geo.size.height - Self.beginRoom - verseHeight - pageTwoHeight) / 2)
            let topPad = lock.focus ? pageTwoTop : pageOneTop
            // The verse alone starts in the very middle, then rises to its place.
            let fromMiddle = geo.size.height / 2 - (topPad + verseHeight / 2)
            ZStack {
                // The page's own colour over the blurred wheel; plain (opaque) once the narration is up.
                theme.backdrop.opacity(lock.focus ? 1 : 0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { hurry() }
                    .animation(.easeInOut(duration: 0.6), value: lock.focus)

                VStack(spacing: 0) {
                    Color.clear.frame(height: topPad)
                    verse
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { verseHeight = $0 }
                        .offset(y: stage <= 1 ? fromMiddle : 0)
                        .opacity(stage >= 1 && !leaving && !third ? 1 : 0)
                    ZStack(alignment: .top) {
                        pageOne
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageOneHeight = $0 }
                            .opacity(lock.focus || leaving ? 0 : 1)
                            .allowsHitTesting(!lock.focus && !leaving)
                        pageTwo
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageTwoHeight = $0 }
                            .opacity(lock.focus && !leaving && !third ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    begin
                }
                .padding(.horizontal, 28)

                if third {
                    pageThree
                        .padding(.horizontal, 28)
                        .opacity(leaving ? 0 : 1)
                        .transition(.opacity)
                }

                if lock.focus { close }
            }
            // A tap anywhere while page 1 is still building hurries it along (owner: "some people may not have
            // patience … if they tap it, it speeds it up"); Unlock now keeps its own tap.
            .contentShape(Rectangle())
            .onTapGesture { hurry() }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .fontDesign(.rounded)
        .onChange(of: sharedState.horizontalPage == .zikr, initial: true) { _, here in
            here ? arrive() : leave()
        }
        .onDisappear { run?.cancel(); lock.focus = false }
    }

    // MARK: the words

    private var verse: some View {
        VStack(spacing: 9) {
            Text(ZikrLockWords.verseArabic)
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 36))
                .foregroundStyle(Color.primary.opacity(0.88))
            Text(ZikrLockWords.verseEnglish)
                .font(.system(size: 19, weight: .light, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.82))
                .multilineTextAlignment(.center)
            Text(ZikrLockWords.verseSource.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(Color.primary.opacity(0.4))
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var pageOne: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 36, height: 1)
                .padding(.top, 28)
                .opacity(stage >= 3 ? 1 : 0)
            Text("WHAT'S INSIDE")
                .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.4)
                .foregroundStyle(Color.primary.opacity(0.38))
                .padding(.top, 28)
                .opacity(stage >= 3 ? 1 : 0)
            HStack(alignment: .top, spacing: 22) {
                ForEach(Array(ZikrLockWords.inside.enumerated()), id: \.offset) { i, item in
                    insideItem(item.symbol, item.words)
                        .opacity(itemsShown > i ? 1 : 0)
                        .offset(y: itemsShown > i || reduceMotion ? 0 : 6)
                }
            }
            .padding(.top, 16)
            unlock
                .padding(.top, 34)
                .opacity(stage >= 4 ? 1 : 0)
                .allowsHitTesting(stage >= 4)
            Text("with a two-minute tour")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.4))
                .padding(.top, 4)
                .opacity(stage >= 4 ? 1 : 0)
        }
    }

    private func insideItem(_ symbol: String, _ words: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.sage)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.sage.opacity(0.12)))
            Text(words)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 92)
        .accessibilityElement(children: .combine)
    }

    /// Page 2: the narration in one size and one shade (owner: "keep the narration the same font"), its source, then —
    /// after some room — the bridge to shukr (owner: keep only the bottom part of the old third page, on this one).
    private var pageTwo: some View {
        VStack(spacing: 0) {
            Text(ZikrLockWords.narrationHeading.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.4)
                .foregroundStyle(Color.sage)
                .padding(.top, 34)
                .opacity(linesShown >= 1 ? 1 : 0)
            quote
                .padding(.top, 16)
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 36, height: 1)
                .padding(.top, 30)
                .opacity(linesShown >= ZikrLockWords.narration.count + 3 ? 1 : 0)
            VStack(spacing: 8) {
                Text(ZikrLockWords.firstStep)
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.88))
                Text(ZikrLockWords.bridge)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineSpacing(3)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
            .padding(.top, 30)
            .opacity(linesShown >= ZikrLockWords.narration.count + 3 ? 1 : 0)
            .offset(y: linesShown >= ZikrLockWords.narration.count + 3 || reduceMotion ? 0 : 6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The narration and its source, set as a quote in the app's pressed well (owner: "visually shows its a quote …
    /// maybe box it in a container?"; decision zikr-lock-quote-box A).
    private var quote: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                ForEach(Array(ZikrLockWords.quoteParts.enumerated()), id: \.offset) { _, part in
                    VStack(spacing: 4) {
                        ForEach(part, id: \.index) { line in
                            Text(line.text)
                                .font(.system(size: 16, weight: .light, design: .rounded))
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .modifier(WipeIn(progress: quoteShown > line.index ? 1 : 0))
                        }
                    }
                }
            }
            Text(ZikrLockWords.narrationSource.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.2)
                .foregroundStyle(Color.primary.opacity(0.35))
                .opacity(linesShown >= ZikrLockWords.narration.count + 2 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 22)
        .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), radius: 6, offset: 4))
        .padding(.horizontal, -12)
        .opacity(linesShown >= 2 ? 1 : 0)
    }

    private var pageTwoDone: Bool { linesShown >= ZikrLockWords.narration.count + 4 }

    /// Begin → the Zikr Tour, once everything here has faded.
    private var begin: some View {
        Button {
            triggerSomeVibration(type: .medium)
            run?.cancel()
            toFirstZikr()
        } label: {
            // Unlock's armed look (owner: the bordered button from page 1's second tap).
            HStack(spacing: 6) {
                Text(ZikrLockWords.beginButton)
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.sage)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(Color.sage.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.sage, lineWidth: 1.5))
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
        .opacity(lock.focus && !leaving && !third && pageTwoDone ? 1 : 0)
        .allowsHitTesting(lock.focus && !leaving && !third && pageTwoDone)
    }

    /// Page 3: the first zikr, ready (owner: "they don't know what a task is … they might not even know this zikr …
    /// enough context where it feels comfortable and not over explaining"; "segment it so it shows the logic clear of how
    /// we built the task from the zikr"). Two parts joined by a line: THE ZIKR in the pressed well (what to say, how to
    /// say it, what it means, its source, Listen), then YOUR DAILY TASK — its circle and one line on what it is.
    private var pageThree: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            sectionLabel("The zikr")
                .opacity(thirdShown >= 1 ? 1 : 0)
            VStack(spacing: 14) {
                zikrWords
                    .opacity(thirdShown >= 1 ? 1 : 0)
                thirdSource
                    .opacity(thirdShown >= 2 ? 1 : 0)
                listen
                    .opacity(thirdShown >= 2 ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.vertical, 20)
            .background(NeuPressed(shape: RoundedRectangle(cornerRadius: 22, style: .continuous), radius: 6, offset: 4))
            .padding(.horizontal, -12)
            .padding(.top, 12)
            .opacity(thirdShown >= 1 ? 1 : 0)
            .offset(y: thirdShown >= 1 || reduceMotion ? 0 : 6)
            // The zikr → its task.
            VStack(spacing: 3) {
                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 22)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .padding(.top, 12)
            .opacity(thirdShown >= 3 ? 1 : 0)
            sectionLabel("Your daily task")
                .padding(.top, 10)
                .opacity(thirdShown >= 3 ? 1 : 0)
            firstRing
                .scaleEffect(0.8)
                .frame(height: 166)
                // The tour's thumbprint tapping the circle (owner: "a ghost tap graphic on the task ring"), off the
                // name, with the prompt.
                .overlay {
                    GeometryReader { geo in
                        TouchHint(spec: TouchHintSpec(kind: .tap, at: CGPoint(x: geo.size.width / 2 + 48,
                                                                              y: geo.size.height / 2 + 44)))
                    }
                    .opacity(thirdShown >= 4 ? 1 : 0)
                }
                .padding(.top, 2)
                .opacity(thirdShown >= 3 ? 1 : 0)
                .scaleEffect(thirdShown >= 3 || reduceMotion ? 1 : 0.94)
            taskLine
                .padding(.top, 6)
                .opacity(thirdShown >= 3 ? 1 : 0)
            Spacer(minLength: 0)
            prompt
        }
        .padding(.top, 70)
    }

    private func sectionLabel(_ words: String) -> some View {
        Text(words.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded)).tracking(1.4)
            .foregroundStyle(Color.sage)
    }

    /// The task's own circle, as the wheel draws it (owner: "the task should look like our task rings").
    private var firstRing: some View {
        Button(action: startCounting) {
            ZikrCircleFace(title: firstTask?.title ?? FirstZikr.taskName, icon: nil,
                           subtitle: "0 of \(FirstZikr.goal)", ring: .progress(0),
                           mantraLine: firstTask?.mantraLine,
                           note: firstTask?.estimateNote(TaskProgress(count: 0, seconds: 0)))
                .contentShape(Circle())
                .scaleEffect(breathe ? 1.025 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start \(FirstZikr.name), \(FirstZikr.goal) times")
    }

    /// What to say, how to say it, what it means.
    private var zikrWords: some View {
        VStack(spacing: 8) {
            Text(FirstZikr.arabicLines)
                .font(.custom("KFGQPCUthmanTahaNaskh", size: 25))
                .foregroundStyle(Color.primary.opacity(0.88))
                .lineSpacing(6)
            Text(FirstZikr.sayLines)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .italic()
                .foregroundStyle(Color.primary.opacity(0.5))
                .lineSpacing(2)
            Text("“\(FirstZikr.meaningLines)”")
                .font(.system(size: 16, weight: .light, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.75))
                .lineSpacing(3)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var thirdSource: some View {
        Text(FirstZikr.source.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.2)
            .foregroundStyle(Color.primary.opacity(0.35))
            .multilineTextAlignment(.center)
    }

    /// The circle explained in one line: it's a daily task we made, and how it fills.
    private var taskLine: some View {
        Text(ZikrLockWords.firstTaskLine)
            .font(.system(size: 15, weight: .light, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.65))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var listen: some View {
        if let memo = firstTask?.mantra?.audioData {
            Button { audio.togglePlay(memo) } label: {
                HStack(spacing: 6) {
                    Image(systemName: audio.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(audio.state == .playing ? "Pause" : "Listen")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.sage)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(Color.sage.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var prompt: some View {
        Text("Tap the circle when you're ready")
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Color.sage)
            .padding(.bottom, 36)
            .opacity(thirdShown >= 4 ? 1 : 0)
    }

    /// ✕: back to page 1, still locked.
    private var close: some View {
        Button {
            triggerSomeVibration(type: .light)
            run?.cancel()
            ZikrAudio.stopAll()
            withAnimation(.easeInOut(duration: 0.9)) {
                lock.focus = false
                linesShown = 0
                quoteShown = 0
                third = false
                thirdShown = 0
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.4))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Not now")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 20)
        .padding(.top, 8)
        .transition(.opacity)
    }

    /// "Unlock now" in the app's green; the first tap grows it into a bordered "Tap again to start the tour" (3 s), the
    /// second enters page 2. The tap area is a fixed box the capsule's size, never the moving shape (an animated frame
    /// kept the old tap area — the Skip button's trap).
    private var unlock: some View {
        ZStack {
            Capsule()
                .fill(Color.sage.opacity(armed ? 0.08 : 0))
                .overlay(Capsule().strokeBorder(Color.sage, lineWidth: 1.5).opacity(armed ? 1 : 0))
                .frame(width: (armed ? armedWidth : restWidth) + 32, height: 38)
            ZStack {
                if armed {
                    unlockLabel("Tap again to start the tour", symbol: "checkmark").transition(.blurReplace)
                } else {
                    unlockLabel("Unlock now", symbol: "lock.open.fill").transition(.blurReplace)
                }
            }
        }
        .frame(width: max(armedWidth, restWidth) + 32, height: 38)
        .background {
            ZStack {
                unlockLabel("Tap again to start the tour", symbol: "checkmark").fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { armedWidth = $0 }
                unlockLabel("Unlock now", symbol: "lock.open.fill").fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { restWidth = $0 }
            }
            .hidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tapUnlock)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(armed ? "Tap again to start the tour" : "Unlock now")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { enterFocus() }
    }

    private func unlockLabel(_ words: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold))
            Text(words)
        }
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.sage)
        .lineLimit(1)
    }

    private static let change = Animation.spring(response: 0.38, dampingFraction: 0.82)

    private func tapUnlock() {
        if armed { enterFocus(); return }
        triggerSomeVibration(type: .light)
        token += 1
        let mine = token
        withAnimation(Self.change) { armed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {   // an input timeout
            guard mine == token else { return }
            withAnimation(Self.change) { armed = false }
        }
    }

    // MARK: the moves

    /// Arriving on the Zikr page: page 1 builds itself up (Reduce Motion: it's all there, faded in).
    private func arrive() {
        run?.cancel()
        guard !lock.focus else { return }
        stage = 0; itemsShown = 0; armed = false; leaving = false; third = false; thirdShown = 0
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { stage = 4; itemsShown = ZikrLockWords.inside.count }
            return
        }
        run = Task { @MainActor in
            // Slow and gradual (owner: "fade in more gradual. hold on the verse for a while. and the position change also
            // more gradual"): the verse fades in alone, stays a while, then drifts up; the rest comes in after it.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.6)) { stage = 1 }                             // the verse alone
            try? await Task.sleep(for: .milliseconds(3600))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.8)) { stage = 2 }                             // it drifts up
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.0)) { stage = 3 }                             // what's inside
            for i in 1...ZikrLockWords.inside.count {
                withAnimation(.easeInOut(duration: 0.9)) { itemsShown = i }
                try? await Task.sleep(for: .milliseconds(380))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.0)) { stage = 4 }                             // Unlock now
        }
    }

    /// A tap mid-build: the rest of page 1 quickly — the verse in (if it isn't), up, what's inside, Unlock now — about a
    /// second in all, from wherever it had got to.
    private func hurry() {
        guard !lock.focus, !leaving, stage < 4 else { return }
        run?.cancel()
        run = Task { @MainActor in
            if stage < 1 {
                withAnimation(.easeOut(duration: 0.3)) { stage = 1 }
                try? await Task.sleep(for: .milliseconds(200))
            }
            if stage < 2 {
                withAnimation(.easeInOut(duration: 0.55)) { stage = 2 }
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { stage = 3 }
            for i in max(itemsShown, 0)..<ZikrLockWords.inside.count {
                withAnimation(.easeOut(duration: 0.35)) { itemsShown = i + 1 }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { stage = 4 }
        }
    }

    /// "Remember my Lord": their first zikr's task is made (the intention), and the view turns, in place, into page 3.
    private func toFirstZikr() {
        firstTask = FirstZikr.ensureTask(in: context)
        withAnimation(.easeInOut(duration: 0.8)) { third = true }
        let parts = 4
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) { thirdShown = parts }
            return
        }
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            for i in 1...parts {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9)) { thirdShown = i }
                try? await Task.sleep(for: .milliseconds(i == 2 ? 1400 : 900))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    /// The ring's tap: everything here fades, the tour starts at its counting lessons, and the counter opens on the task.
    private func startCounting() {
        guard let task = firstTask, thirdShown >= 1 else { return }
        triggerSomeVibration(type: .medium)
        ZikrAudio.stopAll()
        run?.cancel()
        withAnimation(.easeInOut(duration: 0.6)) {
            leaving = true
            lock.focus = false
        }
        let id = task.id.uuidString
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            ZikrTour.shared.startFirst(task)
            ZikrFocus.start(id, resume: false)
        }
    }

    /// Leaving the page: ready to build again next time.
    private func leave() {
        run?.cancel()
        withAnimation(.easeIn(duration: 0.15)) { stage = 0; itemsShown = 0 }
        armed = false
    }

    /// The second tap: page 2 grows in place. Everything but the verse steps away, then the narration a line at a time.
    private func enterFocus() {
        triggerSomeVibration(type: .medium)
        run?.cancel()
        armed = false
        // Page 1 fades, the bars step away, and the verse glides to page 2's centred place.
        withAnimation(.easeInOut(duration: 1.1)) { lock.focus = true }
        let lines = ZikrLockWords.narration.count + 4   // heading, the lines, the source, the bridge, Begin
        if reduceMotion {
            quoteShown = ZikrLockWords.quoteLineCount
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) { linesShown = lines }
            return
        }
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            for i in 1...lines {
                guard !Task.isCancelled else { return }
                // 2…(parts + 1) are the quote: the well comes in, then its lines wipe in left to right, one after
                // another (owner), at one reading speed; a breath between the parts, a pause before the source.
                if (3...ZikrLockWords.narration.count + 1).contains(i) { continue }
                if i == 2 {
                    withAnimation(.easeInOut(duration: 0.9)) { linesShown = ZikrLockWords.narration.count + 1 }
                    try? await Task.sleep(for: .milliseconds(450))
                    for line in ZikrLockWords.quoteParts.joined() {
                        guard !Task.isCancelled else { return }
                        let wipe = 0.5 + Double(line.text.count) * 0.02
                        withAnimation(.linear(duration: wipe)) { quoteShown = line.index + 1 }   // one speed across (owner: no easing)
                        try? await Task.sleep(for: .seconds(wipe * 0.8 + (line.endsPart ? 0.35 : 0)))
                    }
                    try? await Task.sleep(for: .milliseconds(700))
                    continue
                }
                withAnimation(.easeInOut(duration: 0.9)) { linesShown = i }
                // A pause before the bridge to shukr.
                try? await Task.sleep(for: .milliseconds(i == lines - 2 ? 1500 : 1050))
            }
        }
    }
}

/// The page's words. The verse is the app's own Quran text and translation (quran.sqlite, english_hilali.sqlite) without
/// the translation's bracketed notes; the narration is sunnah.com's English of Sahih al-Bukhari 7405 with its one
/// bracketed note left out and the hand-span lines skipped.
enum ZikrLockWords {
    static let verseArabic = "فَاذكُرونى أَذكُركُم"
    static let verseEnglish = "“Remember Me; I will remember you.”"
    static let verseSource = "Al-Baqarah 2:152"
    static let inside: [(symbol: String, words: String)] = [
        ("circle.hexagonpath", "A counter for\nany zikr"),
        ("checklist", "Daily goals,\ngently reminded"),
        ("flame", "Streaks that\nkeep you going"),
    ]
    /// Ibn Kathir's tafsir of 2:152 cites this hadith qudsi to explain the verse; the hadith itself wasn't said about it,
    /// so the heading doesn't claim it was.
    /// "Through His Prophet ﷺ": what a hadith qudsi is, in words anyone follows (decision zikr-lock-bridge A).
    static let narrationHeading = "And through His Prophet ﷺ, Allah says"
    static let narration = [
        "I am as My servant thinks I am,\nand I am with him when he remembers Me.",
        "If he remembers Me in himself,\nI remember him in Myself.",
        "If he remembers Me in a gathering,\nI remember him in a gathering better than theirs.",
        "If he comes to Me walking,\nI come to him running.",
    ]
    static let narrationSource = "Sahih al-Bukhari 7405"
    /// The narration as the lines it's shown in, numbered through (each part's own lines, split at "\n").
    struct QuoteLine { let index: Int; let text: String; let endsPart: Bool }
    static let quoteParts: [[QuoteLine]] = {
        var n = 0
        return narration.map { part in
            let lines = part.components(separatedBy: "\n")
            return lines.enumerated().map { i, text in
                defer { n += 1 }
                return QuoteLine(index: n, text: text, endsPart: i == lines.count - 1)
            }
        }
    }()
    static let quoteLineCount = quoteParts.joined().count
    /// The narration's thread carried on (it ends on walking towards Him): the step, then what the tour will do.
    static let firstStep = "So take the first step, however small."
    /// Page 3, under the circle: what the circle is, said once.
    static let firstTaskLine = "We set it up for you: 33 times a day.\nThe circle fills as you count."
    static let bridge = "We'll set up one daily zikr and count it together. It takes about two minutes."
    /// Their first intention, answering the verse's call (owner, 2026-10-08: "a stronger button … the user making their
    /// first intention or promise").
    static let beginButton = "Remember my Lord"
}

/// The first zikr's app-side parts: its bundled recording and its task (the words live with the built-ins).
extension FirstZikr {
    static let memoResource = "first-zikr"
    /// How to say it, one phrase a line (under the Arabic on page 3).
    static let sayLines = "SubhanAllahi wa bihamdihi,\nSubhanAllahil-'Azim"

    /// The recording bundled with the app, when there is one.
    static var bundledMemo: Data? {
        Bundle.main.url(forResource: memoResource, withExtension: "m4a").flatMap { try? Data(contentsOf: $0) }
    }

    /// Its zikr (seeded as a built-in, or made now) and its task, 33 a day — made once; an existing one is reused.
    /// Once: the recording into the built-in zikr when it was seeded without it (the built-ins v2 seed has no audio;
    /// someone already past the lock never runs `ensureTask`). Left alone after that, so a memo removed stays removed.
    @MainActor static func fillMemo(in context: ModelContext) {
        let d = UserDefaults.standard
        let filledKey = "firstZikr.memoFilled"
        guard !d.bool(forKey: filledKey), let memo = bundledMemo else { return }
        let key = BuiltInAzkar.key(name)
        let azkar = (try? context.fetch(FetchDescriptor<MantraModel>())) ?? []
        guard let zikr = azkar.first(where: { $0.builtInID == key }) else { return }
        if zikr.audioData == nil {
            zikr.audioData = memo
            try? context.save()
        }
        d.set(true, forKey: filledKey)
    }

    @MainActor static func ensureTask(in context: ModelContext) -> TaskModel? {
        let key = BuiltInAzkar.key(name)
        let azkar = (try? context.fetch(FetchDescriptor<MantraModel>())) ?? []
        let zikr: MantraModel
        if let found = azkar.first(where: { $0.builtInID == key }) ?? azkar.first(where: { BuiltInAzkar.key($0.name) == key }) {
            zikr = found
        } else {
            zikr = MantraModel(name: name, fullText: arabic, notes: note)
            zikr.builtInID = key
            context.insert(zikr)
        }
        if zikr.audioData == nil, let memo = bundledMemo { zikr.audioData = memo }
        if let task = zikr.tasks.first {
            try? context.save()
            return task
        }
        let task = TaskModel(mantra: zikr, isCountMode: true, goal: goal, sortOrder: TaskModel.nextSortOrder(in: context))
        task.customName = taskName
        context.insert(task)
        try? context.save()
        return task
    }
}

/// A line written in from left to right: a soft edge sweeps across it as `progress` goes 0 → 1.
struct WipeIn: ViewModifier, Animatable {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let soft: CGFloat = 0.3
        let edge = progress * (1 + soft) - soft
        content.mask {
            LinearGradient(stops: [.init(color: .black, location: min(max(edge, 0), 1)),
                                   .init(color: .clear, location: min(max(edge + soft, 0), 1))],
                           startPoint: .leading, endPoint: .trailing)
        }
    }
}
