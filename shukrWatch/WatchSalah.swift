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
        // A Friday Dhuhr at one of your masajid is Jumu'ah (full marks), as the phone will score it.
        let masjid = WatchPrayers.jumuahMasjid(for: prayer, near: WatchCompass.shared.recentLocation)
        let score = masjid != nil ? 1 : WatchScoring.score(start: prayer.start, end: prayer.end, at: date)
        // An id per mark: the phone applies it once, however many copies arrive, and an undo names it.
        let id = UUID().uuidString
        WatchStore.addLocalMark(prayer.name, dayStart: day.prayers[0].start, score: score, at: date, id: id)
        WatchStore.clearLocalUnmark(prayer.name)
        WKInterfaceDevice.current().play(.success)
        send(["type": "prayerMarked", "id": id, "name": prayer.name,
              "start": prayer.start.timeIntervalSince1970, "end": prayer.end.timeIntervalSince1970,
              "at": date.timeIntervalSince1970])
        WidgetCenter.shared.reloadAllTimelines()
        WatchSession.shared.refresh()
        WatchNotifications.cancelNudges(for: prayer.name)
        WatchMoment.shared.show(prayer: prayer, score: score, markID: id, jumuahAt: masjid)
    }

    /// Unmark a done prayer from the list (marked on the watch, the phone or the widget): shown
    /// undone at once, and the phone resets it like an in-app unmark. Its own id makes it
    /// idempotent; a watch mark's id rides along so a late copy of that mark is ignored.
    static func unmark(_ prayer: WatchPrayer) {
        guard let day = WatchPrayers.day(at: prayer.start) else { return }
        let markID = WatchStore.localMarkIDs[prayer.name]
        let id = UUID().uuidString
        WatchStore.removeLocalMark(prayer.name)
        WatchStore.addLocalUnmark(prayer.name, dayStart: day.prayers[0].start, id: id)
        // "at": the tap, so the phone ignores this if the prayer was marked again after it.
        var info: [String: Any] = ["type": "prayerUnmarked", "id": id, "byName": true,
                                   "name": prayer.name, "start": prayer.start.timeIntervalSince1970,
                                   "at": Date().timeIntervalSince1970]
        if let markID { info["markID"] = markID }
        send(info)
        WKInterfaceDevice.current().play(.directionDown)
        WidgetCenter.shared.reloadAllTimelines()
        WatchSession.shared.refresh()
    }

    /// Undo (within seconds): the local mark goes, and the phone takes it off again. Until the
    /// phone reports the undo handled (its id — the mark's own — under unmarkIDs), a pending local
    /// unmark keeps it shown undone, even if the phone had already confirmed the mark or is out of
    /// reach.
    static func undo(_ prayer: WatchPrayer, markID: String) {
        let dayStart = WatchPrayers.day(at: prayer.start)?.prayers[0].start ?? prayer.start
        WatchStore.removeLocalMark(prayer.name)
        WatchStore.addLocalUnmark(prayer.name, dayStart: dayStart, id: markID)
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
        #if DEBUG
        if offline { return }   // the self-test: queued only, as when the phone is out of reach
        #endif
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(info)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(info, replyHandler: nil) { error in
                print("⌚️ not delivered directly: \(error.localizedDescription)")
            }
        }
    }

    /// The phone has handled these (its context's "markIDs" / "unmarkIDs"). A mark leaves the
    /// outbox once the phone has it or its undo; an undo only once the phone has the undo.
    static func confirm(marks: [String], undos: [String]) {
        let marked = Set(marks), undone = Set(undos)
        let box = outbox
        let kept = box.filter { entry in
            let id = entry.value["id"] as? String ?? ""
            switch entry.value["type"] as? String {
            case "prayerMarked": return !marked.contains(id) && !undone.contains(id)
            case "prayerUnmarked": return !undone.contains(id)
            default: return true
            }
        }
        if kept.count != box.count { outbox = kept }
    }

    #if DEBUG
    static var offline = false

    /// `-demoWatchSettleTest` (simulator): Undo after the phone confirmed the mark, with the phone
    /// out of reach, then back. Made-up prayer name; nothing is sent; cleans up.
    static func undoSelfTest() -> [String] {
        offline = true
        defer { offline = false }
        var lines: [String] = []
        func check(_ name: String, _ ok: Bool) { lines.append("\(ok ? "✅" : "❌") \(name)") }
        let prayer = WatchPrayer(name: "TestUndo", start: Date(), end: Date().addingTimeInterval(3600))
        let id = "st-undo-\(UUID().uuidString)"
        let key = "prayerUnmarked-\(id)"
        WatchStore.addLocalMark(prayer.name, dayStart: prayer.start, score: 0.9, at: Date(), id: id)
        WatchStore.save(["markIDs": [id]])                      // the phone confirmed the mark
        check("confirmed mark settled", WatchStore.localMarks[prayer.name] == nil)
        undo(prayer, markID: id)                                // Undo, phone out of reach
        check("undo leaves a pending unmark (shown undone)",
              WatchStore.localUnmarks[prayer.name] != nil && WatchStore.localUnmarkIDs[prayer.name] == id)
        check("undo waits in the outbox", outbox[key] != nil)
        // A context sent before the undo reached the phone still lists the mark as applied.
        WatchStore.save(["markIDs": [id]])
        confirm(marks: [id], undos: [])
        check("stale context: still undone, still queued",
              WatchStore.localUnmarks[prayer.name] != nil && outbox[key] != nil)
        // Back in reach: the phone handled the undo (tombstone → unmarkIDs).
        WatchStore.save(["unmarkIDs": [id]])
        confirm(marks: [], undos: [id])
        check("reconnect: pending unmark settled, outbox cleared",
              WatchStore.localUnmarks[prayer.name] == nil && WatchStore.localUnmarkIDs[prayer.name] == nil && outbox[key] == nil)
        WatchStore.clearLocalUnmark(prayer.name)
        outbox = outbox.filter { $0.key != key }
        return lines
    }
    #endif

    /// A mark the phone couldn't save isn't retried behind the user's back.
    static func drop(markID: String) {
        outbox = outbox.filter { ($0.value["id"] as? String) != markID }
    }

    /// The phone is in reach: everything in the outbox from the last day, directly.
    static func flushOutbox() {
        let cutoff = Date().addingTimeInterval(-86_400).timeIntervalSince1970
        let kept = outbox.filter { ($0.value["queuedAt"] as? Double ?? 0) > cutoff }
        outbox = kept
        guard WCSession.isSupported(), WCSession.default.isReachable else { return }
        // In the order they were made (mark A, undo A, mark B must stay in that order).
        for info in kept.values.sorted(by: { ($0["queuedAt"] as? Double ?? 0) < ($1["queuedAt"] as? Double ?? 0) }) {
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
        /// Jumu'ah at this masjid (the moment says "Jumu'ah", not a clock grade, like the phone).
        var jumuahAt: String? = nil
    }
    @Published private(set) var moment: Moment?
    /// The phone's CompletionFlourish runs for its first 1.8 s; the ring then crossfades to the
    /// next prayer while Undo stays for the rest of the 5 s.
    @Published private(set) var flourish: Moment?
    /// The prayer the tasbih offer is for, and when it goes (the next prayer's start).
    @Published private(set) var offer: (name: String, until: Date)?
    private var token = 0

    func show(prayer: WatchPrayer, score: Double, markID: String, jumuahAt: String? = nil) {
        token += 1
        let t = token
        let m = Moment(prayer: prayer, score: score, markID: markID, at: Date(), jumuahAt: jumuahAt)
        withAnimation(.easeOut(duration: 0.25)) {
            moment = m
            flourish = m
            offer = nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + WatchCompletionMoment.duration) {
            guard t == self.token else { return }
            withAnimation(.easeInOut(duration: 0.4)) { self.flourish = nil }
        }
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
        withAnimation(.easeIn(duration: 0.25)) { moment = nil; flourish = nil; offer = nil }
    }

    func dismissOffer() { withAnimation(.easeIn(duration: 0.25)) { offer = nil } }

    /// Still on offer at `now`?
    func offerIsLive(at now: Date) -> Bool { offer.map { now < $0.until } ?? false }
}

/// The phone's CompletionFlourish (PrayerCompletionFX.swift), ported and scaled to the watch's
/// ring: the arc closes from where the prayer was to a full ring in the score colour (0.55 s), a
/// glow breathes in at 0.5 s and out from 0.85 s, "✓ Asr" over the summary in the score colour
/// comes in with a blur, and it all goes after 1.8 s. The ring's own content (already the next
/// prayer) is hidden meanwhile by the home view.
struct WatchCompletionMoment: View {
    let moment: WatchMoment.Moment
    /// The ring's diameter (the phone's 200 pt circle scaled).
    let diameter: CGFloat
    static let duration: Double = 1.8

    @State private var sweep: Double = 0
    @State private var glow: Double = 0
    @State private var showText = false
    /// This run of the flourish: a stale timer from an earlier run never hides the text.
    @State private var run = UUID()

    private var color: Color { WatchScoring.color(forScore: moment.score) }
    private var s: CGFloat { diameter / 200 }
    /// Where the prayer was in its window when it was marked.
    private var progress: Double {
        let p = moment.prayer
        guard p.end > p.start else { return 0 }
        return moment.at.timeIntervalSince(p.start) / p.end.timeIntervalSince(p.start)
    }

    var body: some View {
        ZStack {
            // The ring's track stays (the ring's own is faded out under this).
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 7.7)   // WatchPrayerRing's band
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(color, style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.6 * glow), radius: 12 * s * glow)
                .shadow(color: color.opacity(0.35 * glow), radius: 24 * s * glow)

            if showText {
                VStack(spacing: 4 * s) {
                    HStack(alignment: .center, spacing: 8 * s) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22 * s, weight: .light))
                        Text(moment.jumuahAt != nil ? "Jumu'ah" : moment.prayer.name)
                            .font(.system(size: 32 * s, weight: .light, design: .rounded))
                    }
                    Text(moment.jumuahAt.map { "Jumu'ah at \($0)" } ?? WatchScoring.summary(forScore: moment.score))
                        .font(.system(size: max(15 * s, 11), weight: .thin, design: .rounded))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 14 * s)
                }
                .transition(.blurReplace)
            }
        }
        .onAppear {
            let thisRun = UUID()
            run = thisRun
            sweep = min(max(progress, 0.02), 1)
            withAnimation(.easeInOut(duration: 0.55)) { sweep = 1 }
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) { showText = true }
            withAnimation(.easeOut(duration: 0.3).delay(0.5)) { glow = 1 }
            withAnimation(.easeInOut(duration: 0.8).delay(0.85)) { glow = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration - 0.45) {
                guard run == thisRun else { return }
                withAnimation(.easeIn(duration: 0.4)) { showText = false }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The watch's compass heading, while a view that shows the qibla is up.
final class WatchCompass: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WatchCompass()
    /// Degrees from true north (magnetic if the watch can't tell true north yet); nil = none.
    @Published private(set) var heading: Double?
    /// Location for true north: .notDetermined / .denied / allowed.
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    private var users = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
        // Seeded now, so someone who already allowed location never sees the "qibla" button flash.
        status = manager.authorizationStatus
        #if DEBUG
        // `-demoWatchHeading 40`: the simulator has no compass.
        if UserDefaults.standard.object(forKey: "demoWatchHeading") != nil {
            heading = UserDefaults.standard.double(forKey: "demoWatchHeading")
        }
        #endif
    }

    var available: Bool { heading != nil || CLLocationManager.headingAvailable() }
    func requestPermission() { manager.requestWhenInUseAuthorization() }

    /// Where the watch itself is, if location is allowed and it knows (within half an hour).
    var recentLocation: (lat: Double, lon: Double)? {
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let l = manager.location, Date().timeIntervalSince(l.timestamp) < 1800 else { return nil }
        return (l.coordinate.latitude, l.coordinate.longitude)
    }

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
        DispatchQueue.main.async { self.status = manager.authorizationStatus }
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
    @State private var showDenied = false

    private var relative: Double? {
        guard let bearing = WatchQibla.bearing, let heading = compass.heading else { return nil }
        var d = (bearing - heading).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Location allowed (or a DEBUG heading): the arrow. Otherwise a quiet prompt in its place —
    /// asked only when tapped, never on its own at launch; denied says so instead of pointing by
    /// magnetic north without telling anyone.
    private var allowed: Bool {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "demoWatchHeading") != nil { return true }
        #endif
        return compass.status == .authorizedWhenInUse || compass.status == .authorizedAlways
    }

    var body: some View {
        ZStack {
            if allowed {
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
            } else if compass.available {
                Button {
                    if compass.status == .notDetermined { askWhy = true } else { showDenied = true }
                } label: {
                    Label(compass.status == .notDetermined ? "qibla" : "No location · tap",
                          systemImage: compass.status == .notDetermined ? "location.north" : "location.slash")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(y: -ringDiameter * 0.38)
            }
        }
        .onAppear { setRunning(!wristDown) }
        .onDisappear { setRunning(false) }
        .onChange(of: wristDown) { _, down in setRunning(!down) }
        .alert("Point to the qibla?", isPresented: $askWhy) {
            Button("Allow location") { compass.requestPermission() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("shukr uses your location with the compass to point you to the qibla accurately.")
        }
        .alert("Location is off for shukr", isPresented: $showDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("To point to the qibla, allow it in the Watch app on your iPhone: Privacy › Location Services › shukr.")
        }
        .onChange(of: relative, initial: true) { _, r in
            // Lined up within the accuracy; it only lets go 2° past it, so wobbling on the edge
            // doesn't flicker. One buzz per line-up, re-armed after a second (as on the phone).
            guard let r, allowed else { aligned = false; return }
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

    private func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        on ? compass.start() : compass.stop()
    }
}
