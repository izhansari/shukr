//
//  ShukrWatchApp.swift
//  shukr Watch
//
//  The watch app: today's prayer on the circle and the day's times. Mostly it exists so the
//  complications have a home and so the phone has somewhere to send the location / method / marked
//  prayers (WatchConnectivity → `WatchStore`). Marking prayers happens on the phone. Zikr (swipe
//  right from Salah) lives in WatchZikr.swift.
//

import SwiftUI
import WatchKit
import WatchConnectivity
import WidgetKit
import UserNotifications

@main
struct ShukrWatchApp: App {
    @StateObject private var session = WatchSession.shared

    init() {
        // Before anything else: a background launch from a notification action may arrive first.
        WatchNotifications.register()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoWatchSettleTest") {
            WatchStore.settleSelfTest(extraLines: WatchPrayerMarker.undoSelfTest)
        }
        if ProcessInfo.processInfo.arguments.contains("-demoWatchCrownTest") { WatchCrownGate.selfTest() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .watchLookRoot()
                .environmentObject(session)
        }
        // Woken in the background with a new context from the phone: held until it has been delivered and taken (an
        // empty task let the wake end before the context was processed — audit B16).
        .backgroundTask(.watchConnectivity) { await WatchSession.shared.receivePending() }
    }
}

/// Receives the phone's application context and keeps it in the watch's app-group defaults.
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()
    /// Bumps when new data lands, so the views redraw.
    @Published var revision = 0

    override init() {
        super.init()
        #if DEBUG
        // `-demoWatch`: a standalone watch simulator has no phone to send the context — seed New
        // York, ISNA, Shafi'i so the ring and complications can be looked at.
        if ProcessInfo.processInfo.arguments.contains("-demoWatch") {
            // `-demoWatchAt "24.86,67.0"`: somewhere else instead (a prayer that's on right now).
            let at = (UserDefaults.standard.string(forKey: "demoWatchAt") ?? "").split(separator: ",").compactMap { Double($0) }
            _ = WatchStore.save(at.count == 2
                ? ["lat": at[0], "lon": at[1], "method": 2, "school": 0, "city": "Demo"]
                : ["lat": 40.7128, "lon": -74.006, "method": 2, "school": 0, "city": "New York"])
            WidgetCenter.shared.reloadAllTimelines()
            // `-demoWatchTasks`: two tasks as the phone would send them (a 100-count Subhanallah with a
            // usual pace of 0.9 s, a 5-minute Astaghfirullah) and Tasbih Fatimah's usual pace.
            if ProcessInfo.processInfo.arguments.contains("-demoWatchTasks") { MainActor.assumeIsolated {
                _ = WatchZikrStore.shared.take([
                    "zikrDay": WatchZikrStore.shared.dayStart().timeIntervalSince1970,
                    "zikrTasks": [
                        ["id": "demo-1", "title": "Subhanallah", "name": "Subhanallah", "countMode": true, "goal": 100,
                         "count": 0, "seconds": 0.0, "step": 0, "mantraID": "demo-m1", "pace": 0.9],
                        ["id": "demo-2", "title": "Astaghfirullah", "name": "Astaghfirullah", "countMode": false, "goal": 5,
                         "count": 0, "seconds": 0.0, "step": 0],
                    ],
                    "zikrSessions": [String](), "freestyleStep": 0, "postSalahPace": 0.7,
                    "azkar": ["Bismillah", "Alhamdulillah", "Allahu Akbar", "Astaghfirullah", "Subhanallah"],
                ])
            } }
        }
        #endif
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Redraw now (a prayer was marked on the watch).
    func refresh() { DispatchQueue.main.async { self.revision += 1 } }

    /// A background wake for WatchConnectivity: activate if needed and wait (up to 10 s) until the delivered content has
    /// been handed to the delegate, then let the main-queue work it queued run.
    func receivePending() async {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.activationState != .activated { session.activate() }
        let deadline = Date().addingTimeInterval(10)
        while session.activationState != .activated || session.hasContentPending, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await MainActor.run { }
    }

    /// On the main queue, all of it: `WatchStore.save` settles the watch's own pending marks, which the watch writes on
    /// the main queue — saved here on WatchConnectivity's queue, the two raced (audit B16).
    private func take(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        DispatchQueue.main.async {
            if WatchStore.save(context) {
                WidgetCenter.shared.reloadAllTimelines()
            }
            WatchZikrStore.shared.take(context)   // today's zikr tasks and progress
            WatchPrayerMarker.confirm(marks: context["markIDs"] as? [String] ?? [],
                                      undos: context["unmarkIDs"] as? [String] ?? [])
            for name in context["completed"] as? [String] ?? [] { WatchNotifications.cancelNudges(for: name) }
        }
        DispatchQueue.main.async { self.revision += 1 }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        take(session.receivedApplicationContext)
        DispatchQueue.main.async {
            WatchZikrStore.shared.resendUnconfirmed()
            WatchPrayerMarker.flushOutbox()
        }
    }

    /// Replies from the phone (a mark it couldn't save).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { reply(userInfo) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { reply(message) }

    private var handledFailures: Set<String> = []

    /// The phone couldn't save a mark (the direct and queued copies both report it: handled once,
    /// by mark id). The local mark goes; the failure buzz waits 3 s and is skipped if the phone
    /// has meanwhile reported the prayer done (a retry that worked).
    private func reply(_ info: [String: Any]) {
        guard info["type"] as? String == "markFailed", let id = info["id"] as? String, !id.isEmpty else { return }
        DispatchQueue.main.async {
            guard !self.handledFailures.contains(id), let name = WatchStore.localMarkName(forID: id) else { return }
            self.handledFailures.insert(id)
            WatchPrayerMarker.drop(markID: id)
            let start = (info["start"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date()
            WatchStore.removeLocalMark(name)
            WidgetCenter.shared.reloadAllTimelines()
            self.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let day = WatchPrayers.day(at: start),
                      !WatchPrayers.completed(dayStart: day.prayers[0].start).contains(name) else { return }
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            DispatchQueue.main.async {
                WatchZikrStore.shared.sendUnconfirmedNow()
                WatchPrayerMarker.flushOutbox()
            }
        }
    }

    func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        if let error { print("⌚️ transfer failed: \(error.localizedDescription)") }
    }

    /// A zikr's voice memo from the phone.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        WatchZikrStore.saveMemo(file)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        take(applicationContext)
    }
}

/// The phone's three pages, on the wrist: Zikr ← Salah → Settings (Salah first).
struct WatchRootView: View {
    @State private var page: Int = {
        #if DEBUG
        // `-watchPage 0|1|2`: open on Zikr / Salah / Settings (simulator checks).
        let v = UserDefaults.standard.integer(forKey: "watchPage")
        if UserDefaults.standard.object(forKey: "watchPage") != nil { return v }
        #endif
        return 1
    }()

    var body: some View {
        TabView(selection: $page) {
            WatchZikrPage().tag(0).watchPageBackground()
            WatchHomeView(onScreen: page == 1).tag(1).watchPageBackground()
            WatchSettingsPage().tag(2).watchPageBackground()
        }
        .tabViewStyle(.page)
        // A session the app was closed on: open on Zikr, where it comes back paused.
        .onAppear { if WatchZikrStore.shared.settleDraft() != nil { page = 0 } }
    }
}

/// The Salah page, like the phone's: the ring on its own, and the prayer list brought into view
/// the way the phone's sheet pops up — here as two vertical pages (swipe up or turn the Digital
/// Crown for the list, swipe down or tap the small ring to go back). A vertical page is watchOS's
/// own gesture, so it never fights the sideways page swipes or the system's edge swipes.
struct WatchHomeView: View {
    /// The Salah page is the one showing (not paged to Zikr / Settings).
    var onScreen = true
    @EnvironmentObject var session: WatchSession
    @ObservedObject private var moments = WatchMoment.shared
    @State private var tasbih: WatchCounterConfig?
    @State private var showQiblaMap: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "demoWatchQiblaMap")   // `-demoWatchQiblaMap YES`
        #else
        return false
        #endif
    }()
    @State private var showList: Int = {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "watchSalahList") { return 1 }   // `-watchSalahList YES`
        #endif
        return 0
    }()

    var body: some View {
        TimelineView(.everyMinute) { context in
            let _ = session.revision
            if let day = WatchPrayers.day(at: context.date) {
                let left = day.prayers.count - WatchPrayers.completed(dayStart: day.prayers[0].start).count
                TabView(selection: $showList) {
                    // The ring alone, the chevron hinting the list below (the phone's chevron).
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        ZStack {
                            if let r = WatchPrayers.relevant(at: context.date) {
                                // Hidden (blurred away) while the flourish plays, like the phone's
                                // circle content; the next prayer crossfades in after it.
                                WatchPrayerRing(prayer: r.prayer, current: r.current, now: context.date, showsQibla: true,
                                                onQibla: { showQiblaMap = true })
                                    .opacity(moments.flourish == nil ? 1 : 0)
                                    .blur(radius: moments.flourish == nil ? 0 : 6)
                                    // No hold / tap on the ring while the flourish plays over it.
                                    .allowsHitTesting(moments.flourish == nil)
                            }
                            // Just marked: the phone's completion flourish over the ring.
                            if let m = moments.flourish {
                                WatchCompletionMoment(moment: m, diameter: min(138, WatchScreen.width * 0.72))
                                    .id(m.markID)   // a second mark within 1.8 s replays the sweep
                                    .transition(.opacity)
                            }
                        }
                        // 138 pt on 45 / 46 mm, scaled down on smaller faces so it clears the clock.
                        .frame(width: min(138, WatchScreen.width * 0.72), height: min(138, WatchScreen.width * 0.72))
                        Spacer(minLength: 0)
                        if moments.moment != nil {
                            Button("Undo") { moments.undo() }
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        } else if moments.offerIsLive(at: context.date) {
                            // The phone's post-salah pill, going by itself after 15 s.
                            WatchPostSalahPill(
                                shown: onScreen && showList == 0 && tasbih == nil,
                                onOpen: {
                                    moments.dismissOffer()
                                    tasbih = WatchCounterConfig(postSalah: true)
                                },
                                onDismiss: { moments.dismissOffer() },
                                onExpire: { moments.expireOffer() })
                            .transition(.opacity)
                        } else {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showList = 1 }
                            } label: {
                                VStack(spacing: 0) {
                                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                                    Text(left > 0 ? "\(left) left today" : "all prayed today")
                                        .font(.system(size: 10, weight: .light, design: .rounded))
                                }
                                .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 12)   // clear of the page dots on a 41 mm face
                    .tag(0)

                    // The list alone, fitting on one screen (swipe down or turn the crown to go back).
                    WatchPrayerList(prayers: day.prayers, now: context.date)
                        .padding(.horizontal, 4)
                        .frame(maxHeight: .infinity)
                    .tag(1)
                }
                .tabViewStyle(.verticalPage)
                // A mark made from the list: back up to the ring for the moment.
                .onChange(of: moments.moment) { _, m in
                    if m != nil { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showList = 0 } }
                }
                .fullScreenCover(item: $tasbih) { config in WatchCounterView(config: config).watchLookRoot() }
                .fullScreenCover(isPresented: $showQiblaMap) { WatchQiblaMap().watchLookRoot() }
                #if DEBUG
                // `-demoWatchPostSalah`: open Tasbih Fatimah as if from the pill (simulator).
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-demoWatchUndo") {   // undo 4 s after a mark
                        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { moments.undo() }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-demoWatchOffer") { moments.demoOffer() }
                    if ProcessInfo.processInfo.arguments.contains("-demoWatchPostSalah") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tasbih = WatchCounterConfig(postSalah: true) }
                    }
                }
                #endif
            } else {
                VStack(spacing: 8) {
                    Text("shukr").font(.system(size: 24, weight: .thin, design: .rounded))
                    Text("Open shukr on your iPhone to set your location.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}

/// The phone's prayer list (TodaysPrayerListView), small: only the prayers still to pray, each with
/// the phone's status dot, name and time; the prayed ones fold into "✓ 3 done ⌄" (tap to show
/// them, dots in their score colour, faded); all five come back once the day is done.
struct WatchPrayerList: View {
    let prayers: [WatchPrayer]
    let now: Date
    /// Watched directly: what's done comes from the stored marks, not from `prayers` / `now`,
    /// so without it SwiftUI kept the old list after a mark (its inputs hadn't changed).
    @EnvironmentObject private var session: WatchSession
    @State private var showDone = false
    @State private var unmarking: WatchPrayer?
    /// Rows whose time is flipped (the phone's PrayerButton `timeTap`): one still to come shows "in 2h 5m", a prayed
    /// one its grade and score ("On time · 88"); the current and missed ones don't flip. Back by itself after 3 s.
    @State private var flipped: Set<String> = []
    @State private var flipTokens: [String: Int] = [:]
    static let flipSeconds: TimeInterval = 3

    var body: some View {
        let _ = session.revision
        let dayStart = prayers[0].start
        let done = WatchPrayers.completed(dayStart: dayStart)
        let scores = WatchPrayers.scores(dayStart: dayStart)
        let allDone = done.count >= prayers.count
        let visible = prayers.filter { !done.contains($0.name) || showDone || allDone }
        VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.name) { index, p in
                if index > 0 { Divider().padding(.horizontal, 10) }
                let isDone = done.contains(p.name)
                row(p, done: isDone, score: scores[p.name])
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !done.isEmpty && !allDone {
                if !visible.isEmpty { Divider().padding(.horizontal, 10) }
                Button {
                    WKInterfaceDevice.current().play(.click)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { showDone.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("\(done.count) done")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showDone ? 180 : 0))
                    }
                    .font(.system(size: 12, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, WatchScreen.small ? 4.5 : 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        #if DEBUG
        // `-demoWatchAsk YES`: open "Prayed …?" on the first outstanding prayer; `-demoWatchMark
        // Asr`: mark one (simulator checks).
        .onAppear {
            let done = WatchPrayers.completed(dayStart: prayers[0].start)
            if UserDefaults.standard.bool(forKey: "demoWatchShowDone") { showDone = true }
            // `-demoWatchFlip "Fajr,Asr"`: flip those rows' times, as a tap would.
            for name in (UserDefaults.standard.string(forKey: "demoWatchFlip") ?? "").split(separator: ",") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { flipTime(String(name)) }
            }
            if let name = UserDefaults.standard.string(forKey: "demoWatchUnmarkAsk"),
               let p = prayers.first(where: { $0.name == name }) { unmarking = p }
            if let name = UserDefaults.standard.string(forKey: "demoWatchUnmark"), done.contains(name),
               let p = prayers.first(where: { $0.name == name }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { WatchPrayerMarker.unmark(p) }
            }
            if let name = UserDefaults.standard.string(forKey: "demoWatchMark"), !done.contains(name),
               let p = prayers.first(where: { $0.name == name }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { WatchPrayerMarker.mark(p) }
            }
        }
        #endif
        .alert(unmarking.map { "Unmark \($0.name)?" } ?? "",
               isPresented: Binding(get: { unmarking != nil }, set: { if !$0 { unmarking = nil } }),
               presenting: unmarking) { p in
            Button("Unmark", role: .destructive) { WatchPrayerMarker.unmark(p); unmarking = nil }
            Button("Cancel", role: .cancel) { unmarking = nil }
        } message: { _ in
            Text("It goes back to not prayed, on your iPhone too.")
        }
    }

    /// The row's time, or what it flips to: a prayer still to come → "in 2h 5m", a prayed one → its grade and score
    /// (the phone's PrayerButton `timeTap`); the current and missed ones don't flip. Never shrunk: every row's time the
    /// same size (owner: "the first four are really small, and the last one is really big" — they were scaled to fit).
    private func flipText(_ p: WatchPrayer, future: Bool, done: Bool, score: Double?) -> String? {
        future ? WatchPrayerRing.until(p.start, now: now) : done ? score.map { WatchScoring.summary(forScore: $0) } : nil
    }

    private func timeLabel(_ p: WatchPrayer, flip: String?) -> some View {
        Group {
            if let flip, flipped.contains(p.name) { Text(flip) } else { Text(p.start, style: .time) }
        }
        .font(.system(size: WatchScreen.small ? 13 : 14, weight: .light, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .contentTransition(.opacity)
    }

    /// The dot marks (owner: "only tapping the circle on the list item marks the prayer complete"): one that has
    /// started → marked at once, with the moment + Undo; a done one → "Unmark X?"; one still to come → nothing.
    private func markTap(_ p: WatchPrayer, done: Bool) {
        if done {
            WKInterfaceDevice.current().play(.click)
            unmarking = p
        } else if p.start <= now {
            WatchPrayerMarker.mark(p)
        }
    }

    private func flipTime(_ name: String) {
        WKInterfaceDevice.current().play(.click)
        let on = !flipped.contains(name)
        withAnimation(.easeInOut(duration: 0.2)) { if on { flipped.insert(name) } else { flipped.remove(name) } }
        let token = (flipTokens[name] ?? 0) + 1
        flipTokens[name] = token
        guard on else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flipSeconds) {
            guard flipTokens[name] == token else { return }
            withAnimation(.easeInOut(duration: 0.2)) { _ = flipped.remove(name) }
        }
    }

    private func row(_ p: WatchPrayer, done: Bool, score: Double?) -> some View {
        let future = now < p.start
        let edge = Color.secondary.opacity(future ? 0.2 : 0.5)
        let flip = flipText(p, future: future, done: done, score: score)
        return HStack(spacing: 0) {
            ZStack {
                Circle().strokeBorder(edge, lineWidth: 1)
                if done {
                    Circle().fill(WatchScoring.color(forScore: score ?? 0).opacity(0.35)).padding(1)
                }
            }
            .frame(width: 12, height: 12)
            // The dot's own tap: the dot and the gap to the name, the row's full height (as before: name at 20 pt).
            .frame(width: 20, alignment: .leading)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { markTap(p, done: done) }
            Text(p.name)
                .font(.system(size: WatchScreen.small ? 14 : 15, weight: .light, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            timeLabel(p, flip: flip)
        }
        // Five rows + the "done" row fit one screen on 41 mm and up (no scrolling): the text plus the old 4.5 / 6 pt
        // padding above and below, as the row's height (so the dot's tap area is the row's whole height).
        .frame(minHeight: WatchScreen.small ? 26 : 30)
        // Anywhere else on the row flips the time, like the phone (only where there's something to flip to).
        .contentShape(Rectangle())
        .onTapGesture { if flip != nil { flipTime(p.name) } }
    }
}

/// The phone's main circle, small (owner, 2026-09-27: the watch showed a green sliver draining while
/// the phone showed a nearly full red ring). Same as the phone: a pale band as the track, a thin arc
/// that *fills* as the window passes (butt cap), coloured by the score you'd get marking it now
/// (green Perfect · yellow On time · red Late). A prayer that hasn't started: an empty arc, a dashed
/// track, "NEXT" over a dimmed name. Tap: "ends 5:21 PM" ⇄ "31m left" (before it starts: "at 5:35 AM"
/// ⇄ "in 1h 51m"), with a click.
struct WatchPrayerRing: View {
    let prayer: WatchPrayer
    let current: Bool
    let now: Date
    /// The phone's qibla arrow on the ring (the big ring only).
    var showsQibla = false
    /// The small ring over the list: everything at half size.
    var compact = false
    /// Replaces the tap's own action (the small ring over the list: back up to the ring).
    var onTap: (() -> Void)? = nil
    /// The qibla arrow's tap: the qibla map.
    var onQibla: (() -> Void)? = nil
    @State private var showLeft = false
    /// The flip goes back by itself, like the phone's circle (`flipSeconds`, 3 s); a second tap sooner turns it back.
    @State private var flipToken = 0
    /// The hold to mark it: fills round the ring while pressed (like the phone's circle).
    @State private var holdFill: CGFloat = 0
    /// A hold is cancelled for good once the ring moves on screen during it: a vertical page swipe
    /// that starts on the ring slides the ring along with the finger, so the press alone never
    /// saw the finger move and marked the prayer mid-swipe (owner: "really annoying").
    @State private var holdCancelled = false
    @State private var holdToken = 0
    @State private var ringY: CGFloat = 0
    @State private var pressY: CGFloat?
    private var k: CGFloat { compact ? 0.55 : 1.1 }
    /// The soft ring's band (AliveRingTuning.fine's 6 pt on the phone's 200 pt circle, scaled).
    private var band: CGFloat { 5.5 * k }

    private func cancelHold() {
        holdCancelled = true
        pressY = nil
        holdToken += 1
        withAnimation(.easeOut(duration: 0.15)) { holdFill = 0 }
    }

    private var elapsed: Double {
        guard current, prayer.end > prayer.start else { return 0 }
        return max(0, min(1, now.timeIntervalSince(prayer.start) / prayer.end.timeIntervalSince(prayer.start)))
    }

    /// "31m left" / "1h 5m left".
    private var leftText: String {
        let minutes = max(0, Int(prayer.end.timeIntervalSince(now) / 60))
        if minutes < 1 { return "<1m left" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }

    /// Before it starts: "in 5m" / "in 1h 51m", the phone's `timeUntilStart` (to the minute: the
    /// page redraws once a minute).
    private var untilText: String { Self.until(prayer.start, now: now) }

    /// A prayer's last hour, still not marked: time left is the default and the tap flips to "ends …", staying there
    /// (the phone's PrayerTimeLine, `lastHourLeft`; owner: "in the last 60 minutes, it displays the time left").
    private var lastHour: Bool { current && prayer.end.timeIntervalSince(now) <= 60 * 60 }
    static func until(_ start: Date, now: Date) -> String {
        let minutes = max(0, Int(start.timeIntervalSince(now) / 60))
        if minutes < 1 { return "in <1m" }
        return minutes >= 60 ? "in \(minutes / 60)h \(minutes % 60)m" : "in \(minutes)m"
    }

    var body: some View {
        ZStack {
            // The phone's soft ring (its public look): a raised band in the page's surface, the arc a fine round band
            // the same width with its own glow; a prayer still to come draws its dashes inside the band.
            WatchSoftBand(width: band)
            if !current {
                Circle().stroke(Color.primary.opacity(0.45), style: StrokeStyle(lineWidth: 1.25, dash: [2, 3.5]))
            }
            // Holding to mark: the score arc itself swells and glows in its own colour (no green —
            // nothing may suggest a grade the prayer doesn't have; owner).
            let scoreColor = WatchScoring.color(start: prayer.start, end: prayer.end, at: now)
            Circle()
                .trim(from: 0, to: elapsed)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: band + 3.5 * holdFill * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: scoreColor.opacity(0.45 + 0.25 * holdFill), radius: (4 + 4 * holdFill) * k)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: WatchPrayers.symbol(prayer.name))
                        .font(.system(size: 13 * k, weight: .light))
                    Text(prayer.name)
                        .font(.system(size: 19 * k, weight: .light, design: .rounded))
                }
                .foregroundStyle(current ? Color.primary : Color.primary.opacity(0.55))
                .overlay(alignment: .top) {
                    if !current {
                        Text("next")
                            .font(.system(size: 7 * max(k, 0.8), weight: .medium, design: .rounded))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .offset(y: -14 * k)
                    }
                }
                Group {
                    // Tap flips it, in both states, like the phone's circle.
                    if current {
                        if showLeft != lastHour { Text(leftText) } else { Text("ends ") + Text(prayer.end, style: .time) }
                    } else {
                        if showLeft { Text(untilText) } else { Text("at ") + Text(prayer.start, style: .time) }
                    }
                }
                .font(.system(size: 11 * max(k, 0.8), weight: .light, design: .rounded))
                // The last hour's time left in the name's colour, not grey (owner: "a little more prominent", as on
                // the phone).
                .foregroundStyle(current && lastHour && !showLeft ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
            }
            if showsQibla { WatchQiblaArrow(ringDiameter: 118 * k, onOpenMap: onQibla) }
        }
        .contentShape(Circle())
        // A new prayer on the ring, or the one shown starting, goes back to "ends …" / "at …".
        .onChange(of: prayer.name) { _, _ in showLeft = false }
        .onChange(of: current) { _, _ in showLeft = false }
        .onChange(of: lastHour) { _, _ in showLeft = false }   // the hour begins: its default
        #if DEBUG
        // `-demoWatchHold`: the hold's look, without marking (simulator screenshots).
        .onAppear {
            guard showsQibla, current, ProcessInfo.processInfo.arguments.contains("-demoWatchHold") else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation(.linear(duration: 0.6)) { holdFill = 1 } }
        }
        #endif
        .onTapGesture {
            if let onTap { onTap(); return }
            guard !compact else { return }
            WKInterfaceDevice.current().play(.click)
            withAnimation(.easeInOut(duration: 0.2)) { showLeft.toggle() }
            flipToken += 1
            guard showLeft, !lastHour else { return }
            let token = flipToken
            DispatchQueue.main.asyncAfter(deadline: .now() + WatchPrayerList.flipSeconds) {
                guard token == flipToken else { return }
                withAnimation(.easeInOut(duration: 0.2)) { showLeft = false }
            }
        }
        // Hold to mark it prayed, like the phone's circle.
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
            ringY = y
            if let start = pressY, abs(y - start) > 2 { cancelHold() }
        }
        .onLongPressGesture(minimumDuration: 0.8, maximumDistance: 4, perform: {
            guard current, !compact, !holdCancelled else { return }
            holdToken += 1
            pressY = nil
            holdFill = 0
            WatchPrayerMarker.mark(prayer)
        }, onPressingChanged: { pressing in
            guard current, !compact else { return }
            if pressing {
                holdCancelled = false
                pressY = ringY
                holdToken += 1
                let t = holdToken
                // The fill waits a still moment, so a swipe's first touch shows nothing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    guard t == holdToken, !holdCancelled else { return }
                    withAnimation(.linear(duration: 0.6)) { holdFill = 1 }
                }
            } else {
                pressY = nil
                holdToken += 1
                withAnimation(.easeOut(duration: 0.2)) { holdFill = 0 }
            }
        })
    }
}

/// The phone's prayer-notification categories, registered on the watch too, so a prayer
/// notification on the wrist keeps "I already prayed" / "Nudge in 5 / 10 minutes" (with a watch
/// app installed, watchOS looks for the category in the watch app). If watchOS hands the action to
/// the watch app, it's done here: marked through the watch's own path (to the phone), or a nudge
/// scheduled on the watch. Same identifiers as shukrApp's NotificationDelegate.
final class WatchNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotifications()

    static func register() {
        let center = UNUserNotificationCenter.current()
        let markPrayed = UNNotificationAction(identifier: "MARK_PRAYED_ACTION", title: "I already prayed", options: [])
        let snooze5 = UNNotificationAction(identifier: "SNOOZE_5_ACTION", title: "Nudge in 5 minutes", options: [])
        let snooze10 = UNNotificationAction(identifier: "SNOOZE_10_ACTION", title: "Nudge in 10 minutes", options: [])
        let round2 = UNNotificationAction(identifier: "ROUND2_SNOOZE_5_ACTION", title: "5 more minutes", options: [])
        let confirm = UNNotificationAction(identifier: "ROUND2_CONFIRM_ACTION", title: "Yes", options: [])
        let deny = UNNotificationAction(identifier: "ROUND2_DENY_ACTION", title: "Lol, I'll pray right now!", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "Round1_Snooze", actions: [markPrayed, snooze5, snooze10], intentIdentifiers: []),
            UNNotificationCategory(identifier: "Round2_Snooze", actions: [markPrayed, round2], intentIdentifiers: []),
            UNNotificationCategory(identifier: "Round2_Confirm", actions: [markPrayed, confirm, deny], intentIdentifiers: []),
        ])
        center.delegate = shared
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let original = response.notification.request.content
        let info = original.userInfo
        let subject = original.subtitle.isEmpty ? original.title : original.subtitle
        let prayer: WatchPrayer? = {
            guard let name = info["prayerName"] as? String, let start = info["prayerStart"] as? Double,
                  let end = info["prayerEnd"] as? Double else { return nil }
            return WatchPrayer(name: name, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
        }()
        // The phone's flow (shukrApp's NotificationDelegate), same words and timings.
        switch response.actionIdentifier {
        case "MARK_PRAYED_ACTION":
            // Done only once the mark is recorded and queued for the phone: done first, the watch could be suspended
            // before it was (audit B16).
            DispatchQueue.main.async {
                if let prayer { WatchPrayerMarker.mark(prayer) }
                completionHandler()
            }
        case "SNOOZE_5_ACTION", "SNOOZE_10_ACTION":
            let minutes = response.actionIdentifier == "SNOOZE_5_ACTION" ? 5 : 10
            Self.nudge(after: Double(minutes * 60), title: "It's been \(minutes) minutes", body: subject,
                       info: info, category: "Round2_Snooze", prayer: prayer?.name, then: completionHandler)
        case "ROUND2_SNOOZE_5_ACTION":
            Self.nudge(after: 1, title: "😑 Are you being serious? Another 5 minutes?", body: subject,
                       info: info, category: "Round2_Confirm", prayer: prayer?.name, then: completionHandler)
        case "ROUND2_CONFIRM_ACTION":
            Self.nudge(after: 5 * 60, title: "5 more minutes have passed!", body: subject,
                       info: info, category: "Round1_Snooze", prayer: prayer?.name, then: completionHandler)
        default:
            completionHandler()
        }
    }

    /// A follow-up nudge on the watch, named after its prayer so marking it cancels it.
    private static func nudge(after seconds: TimeInterval, title: String, body: String, info: [AnyHashable: Any],
                              category: String, prayer: String?, then done: @escaping () -> Void) {
        // Without its prayer a nudge couldn't be cancelled by marking it: skip it.
        guard let prayer else { done(); return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { done(); return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.userInfo = info
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.categoryIdentifier = category
            let request = UNNotificationRequest(identifier: "watch-snooze-\(prayer)-\(UUID().uuidString)",
                                                content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false))
            center.add(request) { _ in done() }
        }
    }

    /// Marked (here, or the phone reports it done): no "It's been 5 minutes" after praying.
    static func cancelNudges(for prayer: String) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("watch-snooze-\(prayer)-") }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
