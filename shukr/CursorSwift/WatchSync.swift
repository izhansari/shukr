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

    func start(container: ModelContainer) {
        Task { @MainActor in WatchZikrSync.start(container: container) }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let dayStart = PrayerDay.start()
        var context: [String: Any] = [
            "lat": group?.double(forKey: "lastLatitude") ?? 0,
            "lon": group?.double(forKey: "lastLongitude") ?? 0,
            "method": group?.object(forKey: "calculationMethod") as? Int ?? 2,
            "school": group?.integer(forKey: "school") ?? 0,
            "city": group?.string(forKey: "lastCityName") ?? "",
            "completed": Array(SharedStore.completedPrayerNamesToday()).sorted(),
            "completedDay": dayStart.timeIntervalSince1970,
        ]
        context.merge(MainActor.assumeIsolated { WatchZikrSync.payload() }) { current, _ in current }
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
        if state == .activated { DispatchQueue.main.async { self.send() } }
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
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
