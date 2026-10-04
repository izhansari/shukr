//
//  WatchSync.swift
//  shukr
//
//  Keeps the Apple Watch app / complications fed: the watch computes prayer times itself, so it
//  only needs the location, calculation method, madhab, city, and which prayers are marked today.
//  Sent as the WatchConnectivity application context (only the latest one is kept, delivered even
//  if the watch app isn't running). Sent when the app becomes active / goes to the background and
//  after a prayer is marked; unchanged context isn't resent.
//

import Foundation
import WatchConnectivity
import SwiftData

final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private var lastSent: NSDictionary?

    /// Called from shukrApp.init (the main thread). The container is set before the session
    /// activates, so a queued watch session delivered at launch always has somewhere to go.
    func start(container: ModelContainer) {
        MainActor.assumeIsolated { WatchZikrSync.start(container: container) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Callable from anywhere: the context (which reads SwiftData) is always built on the main
    /// actor — at once when already on the main thread, else hopped there.
    func send() {
        if Thread.isMainThread { MainActor.assumeIsolated { sendNow() } }
        else { Task { @MainActor in self.sendNow() } }
    }

    @MainActor private func sendNow() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let dayStart = PrayerDay.start()
        var context: [String: Any] = [
            "lat": group?.double(forKey: "lastLatitude") ?? 0,
            "lon": group?.double(forKey: "lastLongitude") ?? 0,
            "method": AutoMethod.effectiveMethod(),   // Automatic resolved: the watch only knows real methods
            "school": group?.integer(forKey: "school") ?? 0,
            "city": group?.string(forKey: "lastCityName") ?? "",
            "completed": Array(SharedStore.completedPrayerNamesToday()).sorted(),
            "completedDay": dayStart.timeIntervalSince1970,
        ]
        context.merge(WatchZikrSync.payload()) { current, _ in current }
        guard lastSent != (context as NSDictionary) else { return }
        do {
            try session.updateApplicationContext(context)
            lastSent = context as NSDictionary
        } catch {
            print("⌚️ watch context not sent: \(error)")
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        print("⌚️ phone session: state=\(state.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) \(error?.localizedDescription ?? "")")
        if state == .activated { send() }
    }
    /// Finished watch zikr sessions and memo requests.
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("⌚️ phone: watch reachable=\(session.isReachable)")
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("⌚️ phone got user info \(userInfo["type"] ?? "")")
        WatchZikrSync.receive(userInfo)
    }
    /// The same, sent directly while the watch is in reach.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        WatchZikrSync.receive(message)
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    /// A switch to another watch: the new one has none of what was sent, so forget `lastSent` (it got nothing until
    /// something changed — audit B16) and activate; activation sends.
    func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil
            WCSession.default.activate()
        }
    }
    /// The watch app installed, or another watch paired: send it everything.
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil
            self.sendNow()
        }
    }
}
