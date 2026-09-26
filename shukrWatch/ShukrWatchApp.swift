//
//  ShukrWatchApp.swift
//  shukr Watch
//
//  The watch app: today's prayer on the circle and the day's times. Mostly it exists so the
//  complications have a home and so the phone has somewhere to send the location / method / marked
//  prayers (WatchConnectivity → `WatchStore`). Read-only for now: marking prayers happens on the
//  phone.
//

import SwiftUI
import WatchConnectivity
import WidgetKit

@main
struct ShukrWatchApp: App {
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
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
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func take(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        if WatchStore.save(context) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        DispatchQueue.main.async { self.revision += 1 }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        take(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        take(applicationContext)
    }
}

struct WatchHomeView: View {
    @EnvironmentObject var session: WatchSession

    var body: some View {
        TimelineView(.everyMinute) { context in
            let _ = session.revision
            if let day = WatchPrayers.day(at: context.date) {
                ScrollView {
                    VStack(spacing: 10) {
                        if let r = WatchPrayers.relevant(at: context.date) {
                            WatchPrayerRing(prayer: r.prayer, current: r.current, now: context.date)
                                .frame(width: 118, height: 118)
                        }
                        let done = WatchPrayers.completed(dayStart: day.prayers[0].start)
                        VStack(spacing: 0) {
                            ForEach(day.prayers, id: \.name) { p in
                                let on = p.start <= context.date && context.date < p.end
                                HStack(spacing: 6) {
                                    Image(systemName: done.contains(p.name) ? "checkmark.circle.fill" : WatchPrayers.symbol(p.name))
                                        .font(.system(size: 12))
                                        .foregroundStyle(done.contains(p.name) ? Color.green : .secondary)
                                        .frame(width: 18)
                                    Text(p.name)
                                        .font(.system(size: 15, weight: on ? .semibold : .regular, design: .rounded))
                                    Spacer()
                                    Text(p.start, style: .time)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(on ? .primary : .secondary)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                        if !WatchStore.city.isEmpty {
                            Label(WatchStore.city, systemImage: "location.fill")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                }
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

/// The phone's main circle, small: a thick pale track, the arc draining as the prayer's time runs
/// out, the name and "ends 6:48" / "at 5:32" inside.
struct WatchPrayerRing: View {
    let prayer: WatchPrayer
    let current: Bool
    let now: Date

    private var left: Double {
        guard current, prayer.end > prayer.start else { return 0 }
        return max(0, min(1, prayer.end.timeIntervalSince(now) / prayer.end.timeIntervalSince(prayer.start)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
            Circle()
                .trim(from: 0, to: left)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Image(systemName: WatchPrayers.symbol(prayer.name))
                    .font(.system(size: 14, weight: .light))
                Text(prayer.name)
                    .font(.system(size: 20, weight: .light, design: .rounded))
                Group {
                    if current {
                        Text("ends ") + Text(prayer.end, style: .time)
                    } else {
                        Text("at ") + Text(prayer.start, style: .time)
                    }
                }
                .font(.system(size: 11, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
    }
}
