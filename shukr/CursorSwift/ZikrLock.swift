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

    /// The Zikr Tour has been taken to its end (its own key, so an earlier finish counts).
    private(set) var unlocked = UserDefaults.standard.bool(forKey: ZikrTour.completedKey)

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

/// Frosted glass over the Zikr page and the card on it. Inside the page, so a swipe still pages past it; a tap on the
/// glass does nothing.
struct ZikrLockCover: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nudge = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { nudge += 1 }   // the lock wiggles: here's the way in

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.sage.opacity(0.16))
                        .frame(width: 84, height: 84)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(Color.sage)
                        .symbolEffect(.wiggle, options: .nonRepeating, value: nudge)
                }
                VStack(spacing: 8) {
                    Text("Zikr is locked")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                    Text("A two-minute tour unlocks it: you'll make your first task and count it.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    triggerSomeVibration(type: .medium)
                    ZikrTour.shared.begin(in: context)
                } label: {
                    Label("Unlock with the tour", systemImage: "lock.open.fill")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.sage))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                Text("Your counter, daily tasks, history and azkar are behind it.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 36)
            .accessibilityElement(children: .contain)
        }
        .onAppear { if !reduceMotion { nudge += 1 } }
    }
}
