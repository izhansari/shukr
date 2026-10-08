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
    /// `-zikrLockReset`: locked again (the simulator's walk).
    func debugReset() {
        UserDefaults.standard.set(false, forKey: ZikrTour.completedKey)
        UserDefaults.standard.set(false, forKey: ZikrTour.offeredKey)
        unlocked = false
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
    /// Begin was tapped: everything fades away before the tour comes in.
    @State private var leaving = false
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
                    .onTapGesture {}
                    .animation(.easeInOut(duration: 0.6), value: lock.focus)

                VStack(spacing: 0) {
                    Color.clear.frame(height: topPad)
                    verse
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { verseHeight = $0 }
                        .offset(y: stage <= 1 ? fromMiddle : 0)
                        .opacity(stage >= 1 && !leaving ? 1 : 0)
                    ZStack(alignment: .top) {
                        pageOne
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageOneHeight = $0 }
                            .opacity(lock.focus || leaving ? 0 : 1)
                            .allowsHitTesting(!lock.focus && !leaving)
                        pageTwo
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageTwoHeight = $0 }
                            .opacity(lock.focus && !leaving ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    begin
                }
                .padding(.horizontal, 28)

                if lock.focus { close }
            }
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
            VStack(spacing: 12) {
                ForEach(Array(ZikrLockWords.narration.enumerated()), id: \.offset) { i, line in
                    Text(line)
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(linesShown >= i + 2 ? 1 : 0)
                        .offset(y: linesShown >= i + 2 || reduceMotion ? 0 : 6)
                }
            }
            .padding(.top, 16)
            Text(ZikrLockWords.narrationSource.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.2)
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.top, 16)
                .opacity(linesShown >= ZikrLockWords.narration.count + 2 ? 1 : 0)
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

    private var pageTwoDone: Bool { linesShown >= ZikrLockWords.narration.count + 4 }

    /// Begin → the Zikr Tour, once everything here has faded.
    private var begin: some View {
        Button {
            triggerSomeVibration(type: .medium)
            run?.cancel()
            startTour()
        } label: {
            HStack(spacing: 6) {
                Text(ZikrLockWords.beginButton)
                Image(systemName: "arrow.right").font(.system(size: 14, weight: .semibold))
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.sage)
            .frame(height: 44)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 24)
        .opacity(lock.focus && !leaving && pageTwoDone ? 1 : 0)
        .allowsHitTesting(lock.focus && !leaving && pageTwoDone)
    }

    /// ✕: back to page 1, still locked.
    private var close: some View {
        Button {
            triggerSomeVibration(type: .light)
            run?.cancel()
            withAnimation(.easeInOut(duration: 0.9)) {
                lock.focus = false
                linesShown = 0
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
        stage = 0; itemsShown = 0; armed = false; leaving = false
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

    /// Begin: everything here fades away, the bars come back, and then — a beat later, not all at once — the tour.
    private func startTour() {
        withAnimation(.easeInOut(duration: 0.7)) {
            leaving = true
            lock.focus = false
        }
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            ZikrTour.shared.begin(in: context)
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
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) { linesShown = lines }
            return
        }
        run = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1100))
            for i in 1...lines {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9)) { linesShown = i }
                // The first line held a beat longer; a pause before the bridge to shukr.
                try? await Task.sleep(for: .milliseconds(i == 2 ? 1600 : i == lines - 2 ? 1500 : 1050))
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
    /// The narration's thread carried on (it ends on walking towards Him): the step, then what the tour will do.
    static let firstStep = "So take the first step, however small."
    static let bridge = "We'll set up one daily zikr and count it together. It takes about two minutes."
    static let beginButton = "Take the first step"
}
