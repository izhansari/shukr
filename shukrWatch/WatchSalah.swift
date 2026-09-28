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
    /// Marks it prayed: shown at once, the completion moment (with Undo) plays, and the phone is
    /// told (queued + direct when in reach).
    static func mark(_ prayer: WatchPrayer, at date: Date = Date()) {
        // The prayer's own day (its Fajr), not whatever day it is at the tap.
        guard let day = WatchPrayers.day(at: prayer.start) else { return }
        let score = WatchScoring.score(start: prayer.start, end: prayer.end, at: date)
        // An id per mark: the phone applies it once, however many copies arrive, and an undo names it.
        let id = UUID().uuidString
        WatchStore.addLocalMark(prayer.name, dayStart: day.prayers[0].start, score: score, at: date, id: id)
        WKInterfaceDevice.current().play(.success)
        send(["type": "prayerMarked", "id": id, "name": prayer.name,
              "start": prayer.start.timeIntervalSince1970, "end": prayer.end.timeIntervalSince1970,
              "at": date.timeIntervalSince1970])
        WidgetCenter.shared.reloadAllTimelines()
        WatchSession.shared.refresh()
        WatchMoment.shared.show(prayer: prayer, score: score, markID: id)
    }

    /// Undo (within seconds): the local mark goes, and the phone takes it off again.
    static func undo(_ prayer: WatchPrayer, markID: String) {
        WatchStore.removeLocalMark(prayer.name)
        send(["type": "prayerUnmarked", "id": markID, "name": prayer.name, "start": prayer.start.timeIntervalSince1970])
        WKInterfaceDevice.current().play(.directionDown)
        WidgetCenter.shared.reloadAllTimelines()
        WatchSession.shared.refresh()
    }

    /// Marks and undos also wait in an outbox (a day) and go again whenever the phone comes into
    /// reach — the queued copy can lag, and simulators never deliver it. The phone applies each
    /// id once, and an undo that lands first cancels its mark.
    private static let outboxKey = "watch.outbox"
    private static var outbox: [String: [String: Any]] {
        get { WatchStore.defaults.dictionary(forKey: outboxKey) as? [String: [String: Any]] ?? [:] }
        set { WatchStore.defaults.set(newValue, forKey: outboxKey) }
    }

    private static func send(_ info: [String: Any]) {
        var box = outbox
        box["\(info["type"] ?? "")-\(info["id"] ?? "")"] = info.merging(["queuedAt": Date().timeIntervalSince1970]) { a, _ in a }
        outbox = box
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(info)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(info, replyHandler: nil) { error in
                print("⌚️ not delivered directly: \(error.localizedDescription)")
            }
        }
    }

    /// The phone is in reach: everything in the outbox from the last day, directly.
    static func flushOutbox() {
        let cutoff = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        let kept = outbox.filter { ($0.value["queuedAt"] as? Double ?? 0) > cutoff }
        outbox = kept
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        // Marks before undos, so a flush never lands an undo ahead of its mark needlessly.
        for info in kept.values.sorted(by: { ($0["type"] as? String ?? "") < ($1["type"] as? String ?? "") }) {
            WCSession.default.sendMessage(info, replyHandler: nil, errorHandler: nil)
        }
    }
}

/// The phone's completion moment after a mark, and then its post-salah offer.
/// - moment: the ring's arc sweeps closed in the score colour, "✓ Asr" / "On time · 88", with an
///   Undo for 5 s;
/// - then "Post-salah tasbih?" (the phone's pill) until it's dismissed, started, or the next prayer
///   begins.
final class WatchMoment: ObservableObject {
    static let shared = WatchMoment()

    struct Moment: Equatable {
        let prayer: WatchPrayer
        let score: Double
        let markID: String
        let at: Date
    }
    @Published private(set) var moment: Moment?
    /// The prayer the tasbih offer is for, and when it goes (the next prayer's start).
    @Published private(set) var offer: (name: String, until: Date)?
    private var token = 0

    func show(prayer: WatchPrayer, score: Double, markID: String) {
        token += 1
        let t = token
        withAnimation(.easeOut(duration: 0.3)) { moment = Moment(prayer: prayer, score: score, markID: markID, at: Date()); offer = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard t == self.token else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                self.moment = nil
                // After the moment, the phone's post-salah offer (until the next prayer begins).
                let next = WatchPrayers.day(at: Date())?.prayers.first { $0.start > Date() }?.start
                    ?? Date().addingTimeInterval(3 * 3600)
                self.offer = (prayer.name, next)
            }
        }
    }

    func undo() {
        guard let m = moment else { return }
        token += 1
        WatchPrayerMarker.undo(m.prayer, markID: m.markID)
        withAnimation(.easeIn(duration: 0.25)) { moment = nil; offer = nil }
    }

    func dismissOffer() { withAnimation(.easeIn(duration: 0.25)) { offer = nil } }

    /// Still on offer at `now`?
    func offerIsLive(at now: Date) -> Bool { offer.map { now < $0.until } ?? false }
}

/// The completion moment over the big ring (the phone's CompletionFlourish, small).
struct WatchCompletionMoment: View {
    let moment: WatchMoment.Moment
    @State private var swept = false

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle()
                .trim(from: 0, to: swept ? 1 : 0)
                .stroke(WatchScoring.color(forScore: moment.score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: WatchScoring.color(forScore: moment.score).opacity(0.5), radius: 5)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text(moment.prayer.name)
                }
                .font(.system(size: 20, weight: .light, design: .rounded))
                Text(WatchScoring.summary(forScore: moment.score))
                    .font(.system(size: 12, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { swept = true } }
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
    /// Location not asked for yet (without it the arrow uses magnetic north).
    var needsPermission: Bool { CLLocationManager.headingAvailable() && manager.authorizationStatus == .notDetermined }
    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func start() {
        users += 1
        guard users == 1, CLLocationManager.headingAvailable() else { return }
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 1000
        // True north needs a location fix: without one `trueHeading` is -1 and the magnetic heading
        // is off by the local declination (10–15°, well past the qibla accuracy).
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
    @State private var askWhy = false
    @AppStorage("watch.qiblaAsked") private var asked = false

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
        .onAppear {
            setRunning(!wristDown)
            // The first time the qibla is shown: why the watch wants location, then the system ask.
            if compass.needsPermission && !asked { asked = true; askWhy = true }
        }
        .alert("Point to the qibla?", isPresented: $askWhy) {
            Button("Allow location") { compass.requestPermission() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("shukr uses your location with the compass to point you to the qibla accurately.")
        }
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
