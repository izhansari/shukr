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

    #if DEBUG
    /// `-zikrLockReset`: locked again (the simulator's walk).
    func debugReset() {
        UserDefaults.standard.set(false, forKey: ZikrTour.completedKey)
        UserDefaults.standard.set(false, forKey: ZikrTour.offeredKey)
        unlocked = false
    }
    #endif
}

/// Over the Zikr page (owner, 2026-10-08: "it should look like it's hiding things"): the wheel under it is blurred
/// (ZikrPageView), so its circles show as soft shapes through a wash of the page's colour; on it a small
/// lock, two short lines, and "Unlock now" as coloured words — a tap turns them into a bordered "Tap again to start the
/// tour", the second tap starts it (owner: "a double confirmation tap … or maybe it turns into a bordered button").
/// Inside the page, so a swipe still pages past it; a tap on the glass only wiggles the lock.
struct ZikrLockCover: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SharedStateClass.self) private var sharedState
    @Environment(\.circleTheme) private var theme
    @State private var nudge = 0
    /// The words come in as the page arrives (owner: "transition the text in when we come to this page").
    @State private var wordsIn = false
    @State private var armed = false
    @State private var token = 0
    @State private var edge = false

    var body: some View {
        ZStack {
            pane
                .contentShape(Rectangle())
                .onTapGesture { nudge += 1 }   // the lock wiggles: here's the way in

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.sage)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Color.sage.opacity(0.14)))
                    .symbolEffect(.wiggle, options: .nonRepeating, value: nudge)
                VStack(spacing: 5) {
                    Text("Zikr is locked")
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                    Text("Take the two-minute tour to open your counter, tasks and azkar.")
                        .font(.system(size: 14, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 250)
                }
                unlock
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32)
            .opacity(wordsIn ? 1 : 0)
            .offset(y: wordsIn || reduceMotion ? 0 : 10)
        }
        // Each arrival on the page: the words rise in (and the lock wiggles); leaving, they go, ready for the next time.
        .onChange(of: sharedState.horizontalPage == .zikr, initial: true) { _, here in
            if here {
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) { wordsIn = true }
                if !reduceMotion {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { nudge += 1 }
                }
            } else {
                withAnimation(.easeIn(duration: 0.15)) { wordsIn = false }
            }
        }
    }

    /// Over the whole page: a wash of the page's own colour on the blurred wheel (owner: "i don't like we can see the
    /// border … still see this disconnect at the top"). Glass whitened the page while the strip under the status bar
    /// kept its colour; the page's own colour has no edge to show, and the blurred circles still come through.
    private var pane: some View {
        theme.backdrop.opacity(0.5)
            .ignoresSafeArea()
    }

    /// "Unlock now" in the app's green; the first tap turns it into a bordered "Tap again to start the tour" (for 3 s),
    /// the second starts it. Its width changes at once, never animated (an animated width kept the old tap area —
    /// the Skip button's trap); the border fades.
    private var unlock: some View {
        HStack(spacing: 6) {
            Image(systemName: armed ? "checkmark" : "lock.open.fill")
                .font(.system(size: 13, weight: .bold))
            Text(armed ? "Tap again to start the tour" : "Unlock now")
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(Color.sage)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .overlay(Capsule().strokeBorder(Color.sage, lineWidth: 1.5).opacity(edge ? 1 : 0))
        .fixedSize()
        .contentShape(Capsule())
        .onTapGesture(perform: tap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(armed ? "Tap again to start the tour" : "Unlock now")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { begin() }
    }

    private func tap() {
        if armed {
            begin()
        } else {
            triggerSomeVibration(type: .light)
            token += 1
            let mine = token
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { armed = true }
            withAnimation(.easeIn(duration: 0.18)) { edge = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {   // an input timeout
                guard mine == token else { return }
                withTransaction(instant) { armed = false }
                withAnimation(.easeOut(duration: 0.15)) { edge = false }
            }
        }
    }

    private func begin() {
        triggerSomeVibration(type: .medium)
        armed = false
        edge = false
        ZikrTour.shared.begin(in: context)
    }
}
