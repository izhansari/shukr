//
//  ExploreShukr.swift
//  shukr
//
//  Settings → Explore shukr (owner, ask settings-explore: "a section in settings … where we can market or sell the other
//  features that we have that we don't really talk about, like the widgets, the lock screen widgets, shortcuts, app
//  intent"). Second pass (owner: "graphics or pics the same way we been doing. and a little more detail"; no Fajr alarm or
//  Live Activities here — Settings has them): each feature in a card — a picture in the setup pages' style (the sage
//  panel, today's real times where they help), its name, why it's nice, what's cool about it, and one action.
//

import SwiftUI
import AppIntents

import WidgetKit
import WatchConnectivity

/// What's already set up, read from iOS (owner, third pass: "educate and excite" — so the page leads with what they
/// haven't tried and moves what they use to a quiet list). Siri can't be read, so it's always to try.
@MainActor @Observable final class ExploreState {
    var homeWidget = false
    var moreWidgets = false
    var lockWidget = false
    var notifications = false
    var controls = false
    var watchPaired = false
    var watchInstalled = false
    var memories = false
    var loaded = false

    func load() async {
        let configs: [WidgetInfo] = await withCheckedContinuation { c in
            WidgetCenter.shared.getCurrentConfigurations { c.resume(returning: (try? $0.get()) ?? []) }
        }
        let lock: Set<WidgetFamily> = [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        homeWidget = configs.contains { !lock.contains($0.family) && $0.kind == WidgetKinds.prayers }
        moreWidgets = configs.contains { !lock.contains($0.family) && $0.kind != WidgetKinds.prayers }
        lockWidget = configs.contains { lock.contains($0.family) }
        await NotificationHealth.shared.refresh()
        let a = NotificationHealth.shared.authorization
        notifications = a == .authorized || a == .provisional || a == .ephemeral
        if let added = try? await ControlCenter.shared.currentControls() {
            controls = added.contains { $0.kind.hasPrefix("betternorms.shukr.control") }
        }
        if WCSession.isSupported() {
            let s = WCSession.default
            watchPaired = s.activationState == .activated && s.isPaired
            watchInstalled = watchPaired && s.isWatchAppInstalled
        }
        memories = !PrayerPhotos.all().isEmpty
        loaded = true
    }
}

struct ExploreShukrPage: View {
    @State private var state = ExploreState()

    private typealias Feature = ExploreFeature

    private func isOn(_ f: Feature) -> Bool {
        switch f {
        case .home: state.homeWidget
        case .lock: state.lockWidget
        case .moreWidgets: state.moreWidgets
        case .notifications: state.notifications
        case .controls: state.controls
        case .siri: false
        case .watch: state.watchInstalled
        case .memories: state.memories
        }
    }

    /// The watch card only for someone with a watch.
    private var features: [Feature] { Feature.allCases.filter { $0 != .watch || state.watchPaired } }
    private var toTry: [Feature] { features.filter { !isOn($0) } }
    private var using: [Feature] { features.filter { isOn($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intro
                ForEach(toTry) { card($0).transition(.opacity) }
                if !using.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALREADY USING")
                            .font(.system(.caption, design: .rounded, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(using.enumerated()), id: \.element) { i, f in
                                if i > 0 { Divider().padding(.leading, 56) }
                                // Still readable (owner: using it doesn't mean knowing it): its card, steps open.
                                NavigationLink {
                                    ScrollView { card(f, open: true).padding(16) }
                                        .background(Color(.systemGroupedBackground).ignoresSafeArea())
                                        .navigationTitle(title(f))
                                        .navigationBarTitleDisplayMode(.inline)
                                        .fontDesign(.rounded)
                                } label: { usingRow(f) }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .animation(.easeInOut(duration: 0.3), value: state.loaded)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Explore shukr")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
        .task { await state.load() }
        // Back from the Home Screen or Control Center: what they just added moves to "Already using".
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await state.load() }
        }
    }

    /// What the page is for, and how far along they are.
    private var intro: some View {
        let done = using.count, total = features.count
        return HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5)
                Circle().trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                    .stroke(Color.sage, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(done)/\(total)").font(.system(.footnote, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("shukr beyond the app").font(.system(.title3, design: .rounded, weight: .semibold))
                Text(done == total ? "You're using all of it. Here's what each one does."
                     : "Your prayers on your Lock Screen, your wrist and a swipe away. Each takes under a minute.")
                    .font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private func card(_ f: Feature, open: Bool = false) -> some View { ExploreFeatureCard(feature: f, open: open) }

    private func usingRow(_ f: Feature) -> some View {
        let (symbol, title): (String, String) = switch f {
        case .home: ("square.grid.2x2", "Prayers widget")
        case .lock: ("lock.rectangle", "Lock Screen widgets")
        case .moreWidgets: ("rectangle.3.group", "More widgets")
        case .notifications: ("bell.badge", "Notifications you can answer")
        case .controls: ("switch.2", "Control Center")
        case .siri: ("waveform", "Siri")
        case .watch: ("applewatch", "Apple Watch")
        case .memories: ("photo.stack", "Memories")
        }
        return HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 26)
            Text(title)
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.sage)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

    private func title(_ f: Feature) -> String {
        switch f {
        case .home: "Prayers widget"
        case .lock: "Lock Screen widgets"
        case .moreWidgets: "More widgets"
        case .notifications: "Notifications"
        case .controls: "Control Center"
        case .siri: "Siri"
        case .watch: "Apple Watch"
        case .memories: "Memories"
        }
    }
}


/// The features this page (and the lean Explore, ExploreLean.swift) sells, each with its card.
enum ExploreFeature: String, CaseIterable, Identifiable {
    case home, lock, moreWidgets, controls, siri, notifications, watch, memories
    var id: String { rawValue }
}

/// One feature's card (picture, why, what's good, steps or its action) — this page's cards, and the lean Explore's
/// stories (ExploreLean.swift).
struct ExploreFeatureCard: View {
    let feature: ExploreFeature
    var open = false

    var body: some View {
        let open = open
        switch feature {
        case .home:
            ExploreCard(startOpen: open, title: "Prayers widget",
                        why: "Your prayer at a glance on your Home Screen, and you can mark it without opening shukr.",
                        features: [("checkmark.circle", "Mark it there", "Tap the circle in the corner. It's scored at the tap, like in the app."),
                                   ("circle.dashed", "A ring that grades you", "Green while it's at its best, then yellow, then red as time runs out."),
                                   ("hand.tap", "Tap the ring", "Switch between time left and when it ends. In the last hour it counts down."),
                                   ("list.bullet", "Today at a glance", "The arrow opens all five times. Tap a prayer there to mark it."),
                                   ("square.grid.2x2", "Your corners", "Two buttons of your choice: Qibla, Tasbeeh, Daily Ayah or 99 Names.")],
                        steps: [("hand.tap", "Touch and hold an empty spot on your Home Screen"),
                                ("plus.circle", "Tap Edit, then Add Widget"),
                                ("magnifyingglass", "Search shukr, pick Prayers, tap Add Widget")],
                        note: "Choose its corners by holding it and tapping Edit Widget. Its look is in Settings → Appearance.") { HomeScreenPicture() }
        case .lock:
            ExploreCard(startOpen: open, title: "Lock Screen widgets",
                        why: "See how long is left every time you pick up your phone, without unlocking it.",
                        features: [("circle", "The circle", "The prayer's ring as it fills. In its last hour it shows the minutes left."),
                                   ("rectangle", "The line", "A live countdown to the end, with a bar that fills."),
                                   ("textformat", "Above the clock", "“Asr · ends 6:48 PM”, in a single line."),
                                   ("square.stack", "Zikr and the Names too", "What's left of today's zikr, and the Name of the Day.")],
                        steps: [("lock", "Touch and hold your Lock Screen, then tap Customize"),
                                ("rectangle.on.rectangle", "Pick your Lock Screen, then tap under the clock"),
                                ("magnifyingglass", "Find shukr and tap the ones you want")],
                        note: "For the line above the clock, tap the date instead.") { LockScreenPicture() }
        case .moreWidgets:
            ExploreCard(startOpen: open, title: "More widgets",
                        why: "Zikr, the 99 Names and the Quran on your Home Screen.",
                        features: [("circle.hexagonpath", "Zikr", "Today's tasks and how many are left. Tap a task to start it."),
                                   ("moon.stars", "Name of the Day", "One of Allah's 99 Names each day, with its meaning."),
                                   ("book", "Daily Ayah", "Today's verse, once you've revealed it in shukr. It never spoils the reveal.")],
                        steps: [("hand.tap", "Touch and hold an empty spot on your Home Screen"),
                                ("plus.circle", "Tap Edit, then Add Widget"),
                                ("magnifyingglass", "Search shukr and swipe to the one you want")]) { MoreWidgetsPicture() }
        case .controls:
            ExploreCard(startOpen: open, title: "Control Center",
                        why: "shukr a swipe away, even inside another app.",
                        features: [("clock", "Prayer", "The prayer that's on, or the next one, and its time."),
                                   ("location.north.line", "Qibla and Tasbeeh", "Straight to the qibla map, or your zikr."),
                                   ("book", "Daily Ayah, 99 Names, Memories", "Each opens straight to it.")],
                        steps: [("arrow.down.right", "Swipe down from the top-right corner"),
                                ("plus", "Tap + at the top left, then Add a Control"),
                                ("magnifyingglass", "Search shukr and add the ones you want")],
                        note: "They work on the Lock Screen's buttons and the Action button too.") { ControlCenterPicture() }
        case .siri:
            ExploreCard(startOpen: open, title: "Siri",
                        why: "Ask without picking up your phone. Say “in shukr” at the end.",
                        features: [("clock", "“What's the next prayer in shukr”", "The prayer and how long until it starts."),
                                   ("hourglass", "“How long is left in shukr”", "Time left for the prayer that's on."),
                                   ("checkmark.circle", "“I prayed in shukr”", "Marks it, and tells you how you did."),
                                   ("circle.hexagonpath", "“Start Tasbih Fatimah in shukr”", "Opens straight into 33 · 33 · 34.")],
                        shortcuts: true) { SiriPicture() }
        case .notifications:
            ExploreCard(startOpen: open, title: "Notifications you can answer",
                        why: "Hold a prayer's notification to answer it, without opening shukr.",
                        features: [("checkmark.circle", "“I already prayed”", "Marks it right from the notification."),
                                   ("clock.arrow.circlepath", "“Nudge in 5 minutes”", "Or 10. It comes back when you said."),
                                   ("bell.badge", "Halfway and 30 minutes left", "On Nudge, two more if you haven't marked it yet.")],
                        action: ("Choose your nudges", { openNotificationSettings() })) { NotificationsPicture() }
        case .watch:
            ExploreCard(startOpen: open, title: "Apple Watch",
                        why: "Your prayers and your zikr on your wrist.",
                        features: [("hand.tap", "Mark prayers", "Hold the ring to mark. Undo if you slip."),
                                   ("digitalcrown.horizontal.arrow.clockwise", "Count your way", "Tap, Double Tap with your fingers, or turn the Crown."),
                                   ("location.north.line", "The qibla", "A map that turns with you and taps your wrist when you face it."),
                                   ("applewatch.watchface", "On your watch face", "The prayer's ring as a complication.")],
                        steps: [("applewatch", "Open the Watch app on your iPhone"),
                                ("arrow.down", "Scroll to Available Apps"),
                                ("square.and.arrow.down", "Tap Install next to shukr")]) { WatchPicture() }
        case .memories:
            ExploreCard(startOpen: open, title: "Memories",
                        why: "A photo after you pray, kept day by day.",
                        features: [("camera", "Both cameras at once", "Where you are, and you, after you mark a prayer."),
                                   ("magnifyingglass", "Find any of them", "By prayer, place, note or date. Hijri dates too."),
                                   ("calendar", "On this day", "What you saw a year ago.")],
                        action: ("Open Memories", { MemoriesPresenter.shared.open = true })) { MemoriesPicture() }
        }
    }

    @Environment(\.dismiss) private var dismiss
    /// Back to Settings, on Reminders' Notifications side (where each prayer's nudges are chosen).
    private func openNotificationSettings() {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))   // the pop first, so the scroll lands
            SettingsJump.shared.request(SettingsJump.notifications)
        }
    }

}

// MARK: - The card

struct ExploreCard<Picture: View>: View {
    /// Opened from "Already using": the steps shown from the start.
    var startOpen = false
    let title: String
    let why: String
    /// What's good about it: a symbol, a short name, a line.
    var features: [(String, String, String)] = []
    var steps: [(String, String)]? = nil
    var note: String? = nil
    var action: (String, () -> Void)? = nil
    var shortcuts = false
    @ViewBuilder let picture: () -> Picture
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            picture()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .background {
                    // The setup pages' panel (NotificationDemo, LiveActivityDemo, AlarmDemo).
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [Color.sage.opacity(0.55), Color.sage.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(.title3, design: .rounded, weight: .semibold))
                Text(why).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !features.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(features.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: f.0)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.sage)
                                .frame(width: 26, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.1).font(.system(.subheadline, design: .rounded, weight: .semibold))
                                Text(f.2).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            if let steps {
                if open {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(spacing: 12) {
                                Text("\(i + 1)")
                                    .font(.system(.footnote, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.sage))
                                Text(step.1).font(.system(.subheadline, design: .rounded))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                Image(systemName: step.0).foregroundStyle(.secondary)
                            }
                        }
                        if let note {
                            Text(note).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                primary(open ? "Got it" : "Show me how") {
                    withAnimation(.snappy(duration: 0.3)) { open.toggle() }
                }
            }
            if let action {
                primary(action.0) { action.1() }
            }
            if shortcuts {
                // Opens shukr's own shortcuts in the Shortcuts app (Apple's button, the system's look).
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .onAppear { if startOpen { open = true } }
    }

    /// The card's one button: a sage capsule, full width.
    private func primary(_ title: String, _ tap: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            tap()
        } label: {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.sage)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(Color.sage.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The pictures (drawn, today's real times where they help)

/// The prayer the pictures show: the preset day's (Asr at its 5:50 PM).
struct ShownPrayer {
    let name: String
    let start: Date
    let end: Date
    var minutesLeft: Int { max(1, Int(end.timeIntervalSince(ExplorePreset.now) / 60)) }
    var isOn: Bool { ExplorePreset.now >= start && ExplorePreset.now < end }
    var left: String {
        let m = minutesLeft
        return m >= 60 ? "\(m / 60) hr \(m % 60) min" : "\(m) min"
    }
    var progress: Double {
        let total = end.timeIntervalSince(start)
        return total > 0 ? min(max(ExplorePreset.now.timeIntervalSince(start) / total, 0.05), 0.95) : 0.4
    }
    /// Explore's preset day's prayer (ExplorePreset: the same for everyone, nothing read from the phone).
    static var now: ShownPrayer {
        let w = ExplorePreset.asr
        return ShownPrayer(name: ExplorePreset.prayer, start: w.start, end: w.end)
    }
}

/// A ring like the widget's: a soft track and the arc, sage.
struct MiniRing: View {
    let progress: Double
    var width: CGFloat = 5
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: width)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.sage, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct HomeScreenPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        HStack(spacing: 14) {
            // The Prayers widget, small.
            VStack(spacing: 8) {
                ZStack {
                    MiniRing(progress: p.progress, width: 6).frame(width: 74, height: 74)
                    VStack(spacing: 1) {
                        Image(systemName: prayerIcon(for: p.name)).font(.system(size: 13, weight: .light))
                        Text(p.name).font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                }
                HStack {
                    Image(systemName: "location.north.line")
                    Spacer()
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .semibold))
                    Spacer()
                    Image(systemName: "circle.hexagonpath")
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }
            .padding(12)
            .frame(width: 124, height: 132)
            // The mark check, top left (the widget's own).
            .overlay(alignment: .topLeading) {
                Image(systemName: "circle").font(.system(size: 15, weight: .light)).foregroundStyle(.secondary).padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            // App icons around it, as on a Home Screen.
            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 12) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color(.systemBackground).opacity(0.55))
                                .frame(width: 52, height: 52)
                        }
                    }
                }
            }
        }
    }
}

struct LockScreenPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        VStack(spacing: 10) {
            // The line above the clock.
            Label("\(p.name) · \(p.isOn ? "ends" : "at") \(shortTimePM(p.isOn ? p.end : p.start))", systemImage: prayerIcon(for: p.name))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            // A Lock Screen's clock: no AM / PM.
            Text(Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            HStack(spacing: 12) {
                // The circle: the prayer's ring; in its last hour the time left replaces the symbol ("27m").
                ZStack {
                    Circle().fill(.white.opacity(0.18))
                    Circle().trim(from: 0, to: p.progress).stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90)).padding(5)
                    Group {
                        if p.minutesLeft < 60 { Text("\(p.minutesLeft)m").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                        else { Image(systemName: prayerIcon(for: p.name)).font(.system(size: 15)) }
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                // The line.
                VStack(alignment: .leading, spacing: 2) {
                    Label(p.name, systemImage: prayerIcon(for: p.name)).font(.system(size: 13, weight: .semibold))
                    Text("\(p.left) left").font(.system(size: 12))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.18)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.13, green: 0.2, blue: 0.17), Color(red: 0.06, green: 0.08, blue: 0.08)],
                                   startPoint: .top, endPoint: .bottom))
    }
}

struct ControlCenterPicture: View {
    var body: some View {
        let ours: [Int: (String, String)] = [1: ("location.north.line", "Qibla"), 2: ("circle.hexagonpath", "Tasbeeh")]
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { i in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(ours[i] != nil ? Color(.systemBackground) : Color(.systemBackground).opacity(0.4))
                        if let (symbol, _) = ours[i] {
                            Image(systemName: symbol).font(.system(size: 22, weight: .regular)).foregroundStyle(Color.sage)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(ours[i] != nil ? 0.12 : 0), radius: 5, y: 2)
                    Text(ours[i]?.1 ?? " ").font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

struct SiriPicture: View {
    var body: some View {
        let next = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
            .compactMap { p in ExplorePreset.windows[p].map { (p, $0.start) } }
            .first { $0.1 > ExplorePreset.now }
        VStack(alignment: .leading, spacing: 10) {
            Text("“Next prayer time from shukr”")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color(.systemBackground).opacity(0.6)))
            HStack(spacing: 10) {
                Image(systemName: prayerIcon(for: next?.0 ?? "Fajr")).font(.system(size: 20, weight: .light))
                VStack(alignment: .leading, spacing: 1) {
                    Text(next?.0 ?? "Fajr").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(next.map { "at \($0.1.formatted(date: .omitted, time: .shortened))" } ?? "tomorrow morning")
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
    }
}

struct WatchPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.black)
                .frame(width: 118, height: 140)
            RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Color.primary.opacity(0.25), lineWidth: 5)
                .frame(width: 126, height: 148)
            // The Crown.
            Capsule().fill(Color.primary.opacity(0.35)).frame(width: 7, height: 26).offset(x: 67, y: -18)
            ZStack {
                MiniRing(progress: p.progress, width: 6).frame(width: 82, height: 82)
                VStack(spacing: 1) {
                    Image(systemName: prayerIcon(for: p.name)).font(.system(size: 12))
                    Text(p.name).font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white)
            }
        }
    }
}

struct MemoriesPicture: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let tilt = [-9.0, 6.0, 0.0][i]
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [[Color(red: 0.55, green: 0.66, blue: 0.6), Color(red: 0.75, green: 0.68, blue: 0.55),
                                                   Color(red: 0.42, green: 0.55, blue: 0.62)][i], .white.opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 112, height: 112)
                    .overlay(alignment: .topLeading) {
                        // The front camera, inset (the Locket look).
                        if i == 2 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(red: 0.86, green: 0.78, blue: 0.7))
                                .frame(width: 34, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2))
                                .padding(8)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 3))
                    .rotationEffect(.degrees(tilt))
                    .offset(x: CGFloat(i - 1) * 14)
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
            }
        }
    }
}


/// Three small widgets: Zikr, Name of the Day, Daily Ayah (veiled until revealed).
struct MoreWidgetsPicture: View {
    var body: some View {
        HStack(spacing: 12) {
            tile {
                VStack(spacing: 4) {
                    MiniRing(progress: 0.6, width: 5).frame(width: 46, height: 46)
                        .overlay(Text("2").font(.system(size: 15, weight: .semibold, design: .rounded)))
                    Text("left today").font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            tile {
                VStack(spacing: 4) {
                    Text("ٱلرَّحْمَٰنُ").font(.system(size: 20))
                    Text("Ar-Raḥmān").font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("The Most Merciful").font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            tile {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(Color.primary.opacity(0.15)).frame(width: [62, 70, 54, 40][i], height: 6)
                    }
                    Text("tap to reveal").font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary).padding(.top, 2)
                }
            }
        }
    }

    private func tile<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c()
            .frame(width: 96, height: 96)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.systemBackground)))
            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
    }
}

/// A prayer notification held open: its buttons.
struct NotificationsPicture: View {
    var body: some View {
        let p = ShownPrayer.now
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.sage).frame(width: 30, height: 30)
                    .overlay(Image(systemName: prayerIcon(for: p.name)).font(.system(size: 13)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(p.name) 🟢").font(.system(size: 13, weight: .semibold))
                    Text("Pray by \(shortTimePM(p.end))").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemBackground)))
            VStack(spacing: 0) {
                ForEach(["I already prayed", "Nudge in 5 minutes", "Nudge in 10 minutes"], id: \.self) { b in
                    Text(b).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                    if b != "Nudge in 10 minutes" { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemBackground).opacity(0.85)))
        }
        .frame(width: 240)
    }
}
