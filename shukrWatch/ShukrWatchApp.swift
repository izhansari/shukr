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

@main
struct ShukrWatchApp: App {
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(session)
        }
        // Woken in the background with a new context from the phone.
        .backgroundTask(.watchConnectivity) { }
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
            _ = WatchStore.save(["lat": 40.7128, "lon": -74.006, "method": 2, "school": 0, "city": "New York"])
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Redraw now (a prayer was marked on the watch).
    func refresh() { DispatchQueue.main.async { self.revision += 1 } }

    private func take(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        if WatchStore.save(context) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        DispatchQueue.main.async { WatchZikrStore.shared.take(context) }   // today's zikr tasks and progress
        DispatchQueue.main.async { self.revision += 1 }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        take(session.receivedApplicationContext)
        DispatchQueue.main.async { WatchZikrStore.shared.resendUnconfirmed() }
    }

    /// Replies from the phone (a mark it couldn't save).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { reply(userInfo) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { reply(message) }

    private func reply(_ info: [String: Any]) {
        guard info["type"] as? String == "markFailed", let name = info["name"] as? String else { return }
        WatchStore.removeLocalMark(name)
        WidgetCenter.shared.reloadAllTimelines()
        refresh()
        DispatchQueue.main.async { WKInterfaceDevice.current().play(.failure) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { DispatchQueue.main.async { WatchZikrStore.shared.sendUnconfirmedNow() } }
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
            WatchZikrPage().tag(0)
            WatchHomeView().tag(1)
            WatchSettingsPage().tag(2)
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
    @EnvironmentObject var session: WatchSession
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
                        if let r = WatchPrayers.relevant(at: context.date) {
                            WatchPrayerRing(prayer: r.prayer, current: r.current, now: context.date, showsQibla: true)
                                .frame(width: 138, height: 138)
                        }
                        Spacer(minLength: 0)
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
                    .tag(0)

                    // The list, under a small ring (tap it to go back up).
                    ScrollView {
                        VStack(spacing: 6) {
                            if let r = WatchPrayers.relevant(at: context.date) {
                                WatchPrayerRing(prayer: r.prayer, current: r.current, now: context.date, compact: true,
                                                onTap: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showList = 0 } })
                                    .frame(width: 64, height: 64)
                            }
                            WatchPrayerList(prayers: day.prayers, now: context.date)
                            if !WatchStore.city.isEmpty {
                                Label(WatchStore.city, systemImage: "location.fill")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .tag(1)
                }
                .tabViewStyle(.verticalPage)
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
    @State private var marking: WatchPrayer?

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
                    .contentShape(Rectangle())
                    // Tap an outstanding prayer that has started → "I prayed". Unmarking stays on
                    // the phone.
                    .onTapGesture {
                        guard !isDone, p.start <= now else { return }
                        WKInterfaceDevice.current().play(.click)
                        marking = p
                    }
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
                    .padding(.vertical, 7)
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
            if UserDefaults.standard.bool(forKey: "demoWatchAsk") {
                marking = prayers.first { !done.contains($0.name) && $0.start <= now }
            }
            if let name = UserDefaults.standard.string(forKey: "demoWatchMark"), !done.contains(name),
               let p = prayers.first(where: { $0.name == name }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { WatchPrayerMarker.mark(p) }
            }
        }
        #endif
        .alert(marking.map { "Prayed \($0.name)?" } ?? "", isPresented: Binding(get: { marking != nil }, set: { if !$0 { marking = nil } }),
               presenting: marking) { p in
            Button("I prayed") { WatchPrayerMarker.mark(p); marking = nil }
            Button("Cancel", role: .cancel) { marking = nil }
        } message: { p in
            Text(now > p.end ? "Marked as Qaza, after its window." : "Scored at this moment, like on your iPhone.")
        }
    }

    private func row(_ p: WatchPrayer, done: Bool, score: Double?) -> some View {
        let future = now < p.start
        let edge = Color.secondary.opacity(future ? 0.2 : 0.5)
        return HStack(spacing: 8) {
            ZStack {
                Circle().strokeBorder(edge, lineWidth: 1)
                if done {
                    Circle().fill(WatchScoring.color(forScore: score ?? 0).opacity(0.35)).padding(1)
                }
            }
            .frame(width: 12, height: 12)
            Text(p.name)
                .font(.system(size: 15, weight: .light, design: .rounded))
            Spacer()
            Text(p.start, style: .time)
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}

/// The phone's main circle, small (owner, 2026-09-27: the watch showed a green sliver draining while
/// the phone showed a nearly full red ring). Same as the phone: a pale band as the track, a thin arc
/// that *fills* as the window passes (butt cap), coloured by the score you'd get marking it now
/// (green Perfect · yellow On time · red Late). A prayer that hasn't started: an empty arc, a dashed
/// track, "NEXT" over a dimmed name. Tap: "ends 5:21 PM" ⇄ "31m left", with a click.
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
    @State private var showLeft = false
    private var k: CGFloat { compact ? 0.55 : 1.1 }

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

    var body: some View {
        ZStack {
            // The phone's 200 pt circle has a 12 pt band and a 4 pt arc; scaled to ~118 pt.
            if current {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 7 * k)
            } else {
                Circle().stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 3.5]))
            }
            Circle()
                .trim(from: 0, to: elapsed)
                .stroke(WatchScoring.color(start: prayer.start, end: prayer.end, at: now),
                        style: StrokeStyle(lineWidth: 2.5 * k, lineCap: .butt))
                .rotationEffect(.degrees(-90))
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
                    if current {
                        if showLeft { Text(leftText) } else { Text("ends ") + Text(prayer.end, style: .time) }
                    } else {
                        Text("at ") + Text(prayer.start, style: .time)
                    }
                }
                .font(.system(size: 11 * max(k, 0.8), weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            }
            if showsQibla { WatchQiblaArrow(ringDiameter: 118 * k) }
        }
        .contentShape(Circle())
        // A new prayer on the ring starts on "ends …" again.
        .onChange(of: prayer.name) { _, _ in showLeft = false }
        .onTapGesture {
            if let onTap { onTap(); return }
            guard current, !compact else { return }
            WKInterfaceDevice.current().play(.click)
            withAnimation(.easeInOut(duration: 0.2)) { showLeft.toggle() }
        }
        // Hold to mark it prayed, like the phone's circle.
        .onLongPressGesture(minimumDuration: 0.6) {
            guard current, !compact else { return }
            WatchPrayerMarker.mark(prayer)
        }
    }
}
