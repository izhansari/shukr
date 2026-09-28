//
//  WatchSalah.swift
//  shukr Watch
//
//  Salah on the wrist beyond looking (Sami, 2026-09-27, owner's picks from #14):
//  - `WatchPrayerMarker`: "I prayed" — shown at once (a local mark, scored at the tap by the
//    phone's rule), sent to the phone (queued + direct when in reach), which saves it on the row
//    with the tap time and reconciles the day / streak / widget like a widget mark
//    (`WatchZikrSync.markPrayer`). Unmarking stays on the phone.
//  - `WatchCompass` + `WatchQiblaArrow`: the phone's circle arrow — a chevron on the ring that turns
//    toward the Kaaba from the watch's compass, green with a dot and a tap when you're facing it
//    (within the phone's qibla accuracy setting). The bearing comes from where the phone last was.
//

import SwiftUI
import WatchKit
import WatchConnectivity
import CoreLocation
import WidgetKit

enum WatchPrayerMarker {
    static func mark(_ prayer: WatchPrayer, at date: Date = Date()) {
        // The prayer's own day (its Fajr), not whatever day it is at the tap.
        guard let day = WatchPrayers.day(at: prayer.start) else { return }
        let score = WatchScoring.score(start: prayer.start, end: prayer.end, at: date)
        WatchStore.addLocalMark(prayer.name, dayStart: day.prayers[0].start, score: score, at: date)
        WKInterfaceDevice.current().play(.success)
        // An id per mark: the phone applies it once, however many copies arrive.
        let info: [String: Any] = ["type": "prayerMarked", "id": UUID().uuidString, "name": prayer.name,
                                   "start": prayer.start.timeIntervalSince1970,
                                   "end": prayer.end.timeIntervalSince1970,
                                   "at": date.timeIntervalSince1970]
        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(info)
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(info, replyHandler: nil) { error in
                    print("⌚️ mark not delivered directly: \(error.localizedDescription)")
                }
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        WatchSession.shared.refresh()
    }
}

/// The watch's compass heading, while a view that shows the qibla is up.
final class WatchCompass: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchCompass()
    /// Degrees from true north (magnetic if the watch can't tell true north yet); nil = none.
    @Published private(set) var heading: Double?
    private let manager = CLLocationManager()
    private var users = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
        #if DEBUG
        // `-demoWatchHeading 40`: the simulator has no compass.
        if UserDefaults.standard.object(forKey: "demoWatchHeading") != nil {
            heading = UserDefaults.standard.double(forKey: "demoWatchHeading")
        }
        #endif
    }

    var available: Bool { heading != nil || CLLocationManager.headingAvailable() }

    func start() {
        users += 1
        guard users == 1, CLLocationManager.headingAvailable() else { return }
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000
        // True north needs a location fix: without one `trueHeading` is -1 and the magnetic heading
        // is off by the local declination (10–15°, well past the qibla accuracy).
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        startLocationIfAllowed()
        manager.startUpdatingHeading()
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 {
            manager.stopUpdatingHeading()
            manager.stopUpdatingLocation()
        }
    }

    private func startLocationIfAllowed() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if users > 0 { startLocationIfAllowed() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        DispatchQueue.main.async {
            if let h = self.heading, abs(h - value) < 0.5 { return }
            self.heading = value
        }
    }
}

extension WatchQiblaArrow {
    private func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        on ? compass.start() : compass.stop()
    }
}

/// The phone's qibla arrow on the circle: a chevron that points at the Kaaba, turned by the
/// compass; green, upright, with a dot on the ring and a tap once you're facing it.
struct WatchQiblaArrow: View {
    let ringDiameter: CGFloat
    @ObservedObject private var compass = WatchCompass.shared
    @Environment(\.isLuminanceReduced) private var wristDown
    @State private var aligned = false
    @State private var lastBuzz = Date.distantPast
    @State private var running = false

    private var relative: Double? {
        guard let bearing = WatchQibla.bearing, let heading = compass.heading else { return nil }
        var d = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    var body: some View {
        ZStack {
            if let relative {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(aligned ? Color.green : Color.primary)
                    .opacity(0.55)
                    .offset(y: -ringDiameter * 0.4)
                    .rotationEffect(.degrees(aligned ? 0 : relative))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aligned)
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .offset(y: -ringDiameter / 2)
                    .opacity(aligned ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        // The compass (and the location for true north) only while the arrow can be seen.
        .onAppear { setRunning(!wristDown) }
        .onDisappear { setRunning(false) }
        .onChange(of: wristDown) { _, down in setRunning(!down) }
        .onChange(of: relative, initial: true) { _, r in
            // Lined up within the accuracy; it only lets go 2° past it, so wobbling on the edge
            // doesn't flicker. One buzz per line-up, re-armed after a second (as on the phone).
            guard let r else { aligned = false; return }
            let s = WatchQibla.sensitivity
            let now = aligned ? abs(r) <= s + 2 : abs(r) <= s
            if now != aligned {
                aligned = now
                if now && Date().timeIntervalSince(lastBuzz) > 1 {
                    lastBuzz = Date()
                    WKInterfaceDevice.current().play(.success)
                }
            }
        }
    }
}
