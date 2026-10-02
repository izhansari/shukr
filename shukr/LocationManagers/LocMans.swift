//
//  LocMans.swift
//  shukr
//
//  Created by Izhan S Ansari on 1/30/25.
//

import SwiftUI
import CoreLocation
import WidgetKit
import Combine
import CoreMotion

//used by pulseCircle
struct QiblaSettings {
    @AppStorage("qibla_sensitivity", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")) static var alignmentThreshold: Double = 3.5
    static let minThreshold: Double = 1.0  // More precise
    static let maxThreshold: Double = 15.0 // More forgiving

    /// Older builds' Settings page saved the value to the standard suite while this read the app
    /// group, so the stepper never took. Carry a value set back then over, once.
    static func migrateFromStandardDefaultsIfNeeded() {
        guard let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"),
              group.object(forKey: "qibla_sensitivity") == nil,
              let old = UserDefaults.standard.object(forKey: "qibla_sensitivity") as? Double else { return }
        group.set(old, forKey: "qibla_sensitivity")
    }
}

//MARK: - Env Location Manager
/// (merged MainCircleLocationManager into GlobalLocationManager)

/// The compass stream: heading and qibla, up to ~30 updates a second on a phone. Its own object so
/// only the views that draw the compass (`@EnvironmentObject var compass: CompassState`) re-render
/// per update — never the root (4789a97: publishing heading on EnvLocationManager, which the root
/// holds, re-rendered the whole app and made every Menu picker flicker). Everything here is
/// published only when it really changes.
final class CompassState: ObservableObject {
    /// Degrees from north the top of the phone points: true north whenever iOS has a location
    /// (the qibla is a true bearing), magnetic otherwise. Smoothed.
    @Published var heading: Double = 0
    /// `heading`: signed degrees from where the phone points to the qibla, −180…180 (+ = turn
    /// clockwise). `aligned`: within the qibla-accuracy setting (a little more to leave it, so it
    /// doesn't flicker at the edge), and only with a trustworthy heading and a known location.
    @Published var qibla: (aligned: Bool, heading: Double) = (false, 0)
    @Published var status: CompassStatus = .noLocation
    #if DEBUG
    /// Settings → My Dev Stuff → Compass debug: one line, refreshed once a second.
    @Published var debugLine = ""
    #endif
}

/// "The compass needs calibrating", published only when that flips — so the ☰ badge and the line
/// under the circle can follow it without redrawing with every heading (CompassState publishes up
/// to ~30 times a second). On after ~3 s of an untrustworthy heading, off as soon as it's good.
final class CompassHealth: ObservableObject {
    @Published var needsCalibration = false
    /// "Calibrate compass" (the line under the circle, the ☰ row) → the sheet (PagerChromeView).
    static let openSheet = Notification.Name("CompassHealth.openSheet")
}

/// What the compass can be trusted for right now; the arrow is dashed unless `.ok`.
enum CompassStatus: Equatable {
    case ok
    /// No location yet (fresh install before the first fix): no qibla to point at.
    case noLocation
    /// iOS says the heading can't be trusted (needs calibrating, interference — a car, a magnet).
    case unreliable
}

class EnvLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate { //locman_flag used for the compass in MainCircle and with injection on @Main
    @ObservationIgnored let manager = CLLocationManager()
    
    // Location and Heading Data
    /// Not @Published: no view reads it (the qibla math does), and the root view observes this
    /// object — publishing every GPS fix re-rendered the whole app once a second. PrayerViewModel
    /// follows fixes through `locationUpdates` instead.
    var userLocation: CLLocation?
    let locationUpdates = PassthroughSubject<CLLocation?, Never>()
    @Published var isAuthorized: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// A city the user picked instead of sharing their location (App Review tests denial, and
    /// prayer times shouldn't need GPS). Its coordinate lives in the app group's lastLatitude /
    /// lastLongitude, which the widget already reads. GPS wins whenever it's authorized.
    @Published private(set) var hasManualLocation: Bool =
        UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")?.bool(forKey: "manualLocation") ?? false
    /// GPS when authorized, otherwise the picked city.
    var effectiveLocation: CLLocation? {
        if isAuthorized, let gps = manager.location { return gps }
        return manualLocation
    }
    private var manualLocation: CLLocation? {
        guard hasManualLocation, let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") else { return nil }
        return CLLocation(latitude: group.double(forKey: "lastLatitude"), longitude: group.double(forKey: "lastLongitude"))
    }
    /// Heading + qibla live here (see CompassState). Not @Published on this object on purpose.
    let compass = CompassState()
    let health = CompassHealth()
    private var unreliableSince: Date?

    // MARK: Heading state (see "Heading" below)
    /// Core Motion's fused heading (compass + gyro, like the Compass app); Core Location's raw
    /// heading is the fallback.
    private let motion = CMMotionManager()
    private var motionFrame: CMAttitudeReferenceFrame?
    /// Something wants the heading (the Salah circle, the map): restarted on every return to the app.
    private var headingWanted = false
    /// Set by didBecomeActive (also at launch), so a background relaunch (travel updates) never
    /// starts the compass.
    private var appActive = false
    private var watchdog: Timer?
    private var lastSampleAt = Date.distantPast
    private var lastMotionAt = Date.distantPast
    private var headingReliable = true
    /// The smoothed heading as a point on the unit circle (an average of 359° and 1° is 0°, not 180°).
    private var smoothX = 0.0, smoothY = 0.0, smoothStarted = false
    /// True bearing to the Kaaba from the last known place; nil = no place yet.
    private var qiblaBearing: Double?
    #if DEBUG
    private var samplesThisSecond = 0, restarts = 0
    private var lastRaw = "", lastCL = "–"
    #endif

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = /*kCLLocationAccuracyBest*/ kCLLocationAccuracyNearestTenMeters
        manager.headingFilter = 1   // degrees; no delegate call for sub-degree jitter
        // Known right away, so an authorized launch never shows the location-only setup for a frame.
        authorizationStatus = manager.authorizationStatus
        isAuthorized = authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
        if authorizationStatus == .denied || authorizationStatus == .restricted { noteRevocationIfNeeded() }
        // Allowed again while the app wasn't running: the Salah page shows straight away, so
        // there's no lost page to acknowledge it on (a `comeback` later would pop one up over it).
        if isAuthorized && locationLost { locationLost = false }
        // The qibla from the saved place at once, so the arrow never waits on the first GPS fix.
        setQiblaOrigin(nil)
        // iOS suspends heading updates in the background; restart them on every return.
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setAppActive(true)
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setAppActive(false)
        }
    }
    
    /// FirstRunSetup.isDone (this file is compiled into the widget too, which doesn't have it).
    private static var setupDone: Bool { UserDefaults.standard.bool(forKey: "firstRunSetup.v1") }

    // Modify this method to be called explicitly
    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// The setup's location step (owner: ask for Always). iOS grants While Using first and offers
    /// Always itself later; from While Using this shows the upgrade prompt (once).
    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }
    
    // CL Location Manager Delegate method for authorization changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startLocationServices()
    }
    
    /// Location was allowed and has been turned off since (iOS Settings → Never), with no city:
    /// the app shows "shukr lost your location" (LostLocationView) instead of the whole setup.
    /// Cleared when location comes back or a city is picked.
    @Published private(set) var locationLost: Bool = UserDefaults.standard.bool(forKey: "locationLost") {
        didSet { if locationLost != oldValue { UserDefaults.standard.set(locationLost, forKey: "locationLost") } }
    }

    /// How location came back while "shukr lost your location" was up (Settings, or a picked
    /// city). Set in the same update that clears `locationLost`, so the root keeps that page up
    /// to acknowledge it and hand off to the Salah circle (LostLocationView); it clears this.
    enum Comeback: Equatable { case always, whileUsing, city(String) }
    @Published private(set) var comeback: Comeback?
    func clearComeback() {
        if comeback != nil { comeback = nil }
        if lostPreview { lostPreview = false }
    }

    /// The palette's Play → No location (SalahLook.swift): "shukr lost your location" over the Salah page, then
    /// location coming back and the hand-off — `locationLost`, the authorisation and the saved city are never
    /// touched (the page is not interactive meanwhile).
    @Published private(set) var lostPreview = false
    func playLostPreview() {
        guard !lostPreview, comeback == nil, !locationLost else { return }
        lostPreview = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard let self, self.lostPreview else { return }
            self.comeback = .whileUsing
        }
    }

    /// Location lost while the app is open: the root keeps the Salah page a moment under the lost
    /// page fading in over it (one ring; a branch swap there doesn't animate). Set in the same update
    /// that turns location off.
    @Published private(set) var salahLingers = false
    /// The lost page has faded in over it (LostLocationView); a fallback ends it anyway.
    func endSalahLinger() { if salahLingers { salahLingers = false } }

    /// Location was on and has been turned off: drop the picked city (the best chance of getting
    /// location back is asking for it; a picked city is offered again), and remember it was lost.
    /// Someone who denied from the start and picked a city keeps it. Also run from `init`, so the
    /// first frame of a launch already knows.
    private func noteRevocationIfNeeded() {
        let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        guard group?.bool(forKey: "locationWasAuthorized") == true else { return }
        group?.set(false, forKey: "locationWasAuthorized")
        group?.set(false, forKey: "manualLocation")
        hasManualLocation = false
        locationLost = true
    }

    /// Use a picked city for prayer times and the qibla (see `hasManualLocation`).
    func setManualLocation(_ coordinate: CLLocationCoordinate2D, name: String) {
        if locationLost { comeback = .city(name) }
        locationLost = false
        let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        group?.set(coordinate.latitude, forKey: "lastLatitude")
        group?.set(coordinate.longitude, forKey: "lastLongitude")
        group?.set(name, forKey: "lastCityName")
        group?.set(true, forKey: "manualLocation")
        hasManualLocation = true
        if !isAuthorized { useManualLocation() }
    }

    /// Feed the picked city through the same path a GPS fix takes. The compass works without
    /// location permission, so the qibla still turns.
    private func useManualLocation() {
        guard let location = manualLocation else { return }
        userLocation = location
        locationUpdates.send(location)
        setQiblaOrigin(location)
        startHeading()
    }

    // Function to start location services
    func startLocationServices() {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationLost { comeback = manager.authorizationStatus == .authorizedAlways ? .always : .whileUsing }
            isAuthorized = true
            let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
            if group?.bool(forKey: "locationWasAuthorized") != true { group?.set(true, forKey: "locationWasAuthorized") }
            if locationLost { locationLost = false }
            manager.startUpdatingLocation()
            if qiblaBearing == nil, let cached = manager.location { setQiblaOrigin(cached) }
            startHeading()   // (again: with a location, Core Motion switches to true north)
            // Travel (notes #18): with Always, big moves wake the app — even when it isn't running
            // (iOS relaunches it in the background; shukrApp.init builds this manager again and
            // the fix comes through `locationUpdates` → PrayerViewModel.handleLocationChange:
            // new times, reminders, widgets, the watch, a re-resolved Automatic method).
            if manager.authorizationStatus == .authorizedAlways {
                manager.startMonitoringSignificantLocationChanges()
            } else {
                manager.stopMonitoringSignificantLocationChanges()
            }
        case .notDetermined:
            isAuthorized = false
            // Not before the first-run setup has explained why (its location step asks).
            if Self.setupDone { manager.requestWhenInUseAuthorization() }
        case .denied, .restricted:
            if isAuthorized && !salahLingers {
                salahLingers = true
                // The change arrives as the app resumes, often before it's on screen; the lost page
                // ends this once it has faded in (`endSalahLinger`). A fallback in case it never shows.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.endSalahLinger() }
            }
            isAuthorized = false
            print("Location services are denied or restricted.")
            noteRevocationIfNeeded()
            useManualLocation()
        @unknown default:
            isAuthorized = false
            print("Unknown authorization status.")
        }
    }

    // Function to explicitly start updating location and heading
    func startUpdating() {
        if Self.setupDone { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        startHeading()
    }
    
    // CL Location Manager Delegate method for location updates
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.last
        locationUpdates.send(locations.last)
        setQiblaOrigin(locations.last)
    }
    
    
    // Error handling for location updates
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Manager failed with error: \(error.localizedDescription)")
    }
    
    // MARK: - Heading
    //
    // The arrow used to listen to Core Location's raw magnetic heading only, started once and never
    // checked (compass audit, 2026-09-30): it froze in a car and sometimes on opening the app, was
    // ~9° off in Cary (magnetic vs the qibla's true north), said "aligned" before any location, and
    // its angle wasn't kept to −180…180. Now: Core Motion's fused heading (true north), Core
    // Location as the fallback, restarted on every return to the app and whenever it goes quiet.

    /// The Salah circle / the map want the heading (also on every return to the app).
    func startHeading() {
        headingWanted = true
        guard appActive else { return }
        manager.startUpdatingHeading()
        startMotion()
        startWatchdog()
    }

    private func setAppActive(_ active: Bool) {
        appActive = active
        if active {
            guard headingWanted else { return }
            restartHeading(because: "app active")
            startWatchdog()
        } else {
            #if DEBUG
            CompassLog.write("app inactive")
            #endif
            // Nothing to point while we're not on screen; Core Location suspends its own.
            motion.stopDeviceMotionUpdates()
            watchdog?.invalidate(); watchdog = nil
        }
    }

    private func restartHeading(because reason: String) {
        manager.stopUpdatingHeading()
        manager.startUpdatingHeading()
        motion.stopDeviceMotionUpdates()
        startMotion()
        #if DEBUG
        restarts += 1
        CompassLog.write("restart #\(restarts): \(reason)")
        #endif
    }

    /// Core Motion's heading (what the Compass app uses): compass + gyroscope, so it stays steady
    /// when the compass alone is thrown off. True north needs location permission; magnetic otherwise.
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        if isAuthorized && frames.contains(.xTrueNorthZVertical) { frame = .xTrueNorthZVertical }
        else if frames.contains(.xMagneticNorthZVertical) { frame = .xMagneticNorthZVertical }
        else { return }
        if motion.isDeviceMotionActive && motionFrame == frame { return }
        motion.stopDeviceMotionUpdates()
        motionFrame = frame
        motion.deviceMotionUpdateInterval = 1.0 / 30
        // Not iOS's calibration screen (owner: apps can't open it on demand, so it can't be the
        // fix we point people to) — ours instead (CompassCalibrationSheet, via CompassHealth).
        motion.showsDeviceMovementDisplay = false
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] sample, _ in
            guard let self, let sample, sample.heading >= 0 else { return }
            self.lastMotionAt = Date()
            self.take(sample.heading, reliable: sample.magneticField.accuracy != .uncalibrated, smoothing: 0.25)
        }
    }

    // Core Location's heading: only while Core Motion is quiet (unavailable, or not started yet).
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        #if DEBUG
        lastCL = "\(Int(value.rounded()))° ±\(Int(newHeading.headingAccuracy))"
        #endif
        guard Date().timeIntervalSince(lastMotionAt) > 0.5 else { return }
        // A negative accuracy means iOS couldn't work the heading out; past ~25° it can't be trusted.
        take(value, reliable: newHeading.headingAccuracy >= 0 && newHeading.headingAccuracy <= 25, smoothing: 0.5)
    }

    /// Never iOS's calibration screen (see `startMotion`): ours is offered instead.
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }

    /// One reading, from either source: smoothed, then published only on a real change.
    private func take(_ degrees: Double, reliable: Bool, smoothing: Double) {
        lastSampleAt = Date()
        #if DEBUG
        samplesThisSecond += 1
        lastRaw = "\(Int(degrees.rounded()))°"
        #endif
        let r = degrees * .pi / 180
        if smoothStarted {
            smoothX += (cos(r) - smoothX) * smoothing
            smoothY += (sin(r) - smoothY) * smoothing
        } else {
            smoothX = cos(r); smoothY = sin(r); smoothStarted = true
        }
        var heading = atan2(smoothY, smoothX) * 180 / .pi
        if heading < 0 { heading += 360 }
        let reliabilityChanged = reliable != headingReliable
        headingReliable = reliable
        if abs(Self.signed(heading - compass.heading)) >= 0.5 { compass.heading = heading }
        else if !reliabilityChanged { return }
        updateQibla()
    }

    /// A second without a reading (the arrow would freeze): start both sources again.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkHeading() }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkHeading() {
        guard appActive, headingWanted else { return }
        let quiet = Date().timeIntervalSince(lastSampleAt)
        // Core Motion reads ~30 times a second; Core Location only when the phone turns (1° filter),
        // so without Core Motion a still phone is quiet on purpose — give it longer.
        if quiet > (motion.isDeviceMotionAvailable ? 2 : 6) {
            restartHeading(because: "quiet \(String(format: "%.1f", quiet))s")
        }
        // Calibration: only after ~3 s of a bad heading (a brief dip shouldn't light the ☰ badge).
        if compass.status == .unreliable {
            let since = unreliableSince ?? Date()
            unreliableSince = since
            if Date().timeIntervalSince(since) >= 3, !health.needsCalibration { health.needsCalibration = true }
        } else {
            unreliableSince = nil
            if compass.status == .ok, health.needsCalibration { health.needsCalibration = false }
        }
        #if DEBUG
        let source = motion.isDeviceMotionActive ? (motionFrame == .xTrueNorthZVertical ? "CM true" : "CM mag") : "CL"
        let bearing = qiblaBearing.map { "\(Int($0.rounded()))°" } ?? "–"
        let first = "\(source) \(lastRaw) · CL \(lastCL) · \(samplesThisSecond)/s · quiet \(String(format: "%.1f", quiet))s"
        let second = "qibla \(bearing) · off \(Int(compass.qibla.heading.rounded()))° · \(compass.status)"
            + "\(compass.qibla.aligned ? " · aligned" : "") · restarts \(restarts)"
        if UserDefaults.standard.bool(forKey: "compassDebug") { compass.debugLine = first + "\n" + second }
        CompassLog.write(first + " · " + second)
        samplesThisSecond = 0
        #endif
    }

    /// Where the qibla is measured from: a fix, else iOS's cached one, else the saved prayer place.
    private func setQiblaOrigin(_ location: CLLocation?) {
        var coordinate = location?.coordinate
        if coordinate == nil, let group = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            let lat = group.double(forKey: "lastLatitude"), lon = group.double(forKey: "lastLongitude")
            if lat != 0 || lon != 0 { coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon) }
        }
        qiblaBearing = coordinate.map(Self.bearingToKaaba)
        updateQibla()
    }

    /// The arrow's angle and "aligned", published only on change. No place yet → not aligned (it
    /// used to say aligned, since the bearing came back as 0).
    private func updateQibla() {
        let status: CompassStatus = qiblaBearing == nil ? .noLocation : headingReliable ? .ok : .unreliable
        if compass.status != status {
            #if DEBUG
            CompassLog.write("status \(compass.status) → \(status)")
            #endif
            compass.status = status
        }
        guard let bearing = qiblaBearing else {
            if compass.qibla.aligned || compass.qibla.heading != 0 { compass.qibla = (false, 0) }
            return
        }
        let off = Self.signed(bearing - compass.heading)
        let threshold = QiblaSettings.alignmentThreshold
        // A little more to leave than to enter, so it doesn't flicker (and buzz) at the edge.
        let aligned = status == .ok && abs(off) <= (compass.qibla.aligned ? threshold + 1.5 : threshold)
        if aligned != compass.qibla.aligned || abs(off - compass.qibla.heading) >= 0.5 {
            compass.qibla = (aligned, off)
        }
    }

    #if DEBUG
    /// `-demoCompassJiggle` (the simulator has no compass): a reading through the real path.
    /// `around`: degrees relative to the qibla instead of north.
    private static let debugStart = Date()
    func debugHeading(_ degrees: Double, around qibla: Bool) {
        let value = qibla ? (qiblaBearing ?? 0) + degrees : degrees
        // `-demoCompassUnreliable`: as if iOS said the heading can't be trusted (the dashed arrow,
        // the line, the ☰ badge); `-demoCompassRecover <s>`: it comes good that many seconds in.
        var reliable = !ProcessInfo.processInfo.arguments.contains("-demoCompassUnreliable")
        let recover = UserDefaults.standard.double(forKey: "demoCompassRecover")
        if !reliable, recover > 0, Date().timeIntervalSince(Self.debugStart) > recover { reliable = true }
        take((value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360), reliable: reliable, smoothing: 0.5)
    }
    #endif

    /// −180…180.
    static func signed(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// The great-circle bearing to the Kaaba, from true north.
    static func bearingToKaaba(from c: CLLocationCoordinate2D) -> Double {
        let lat = c.latitude * .pi / 180, lon = c.longitude * .pi / 180
        let kLat = 21.4225 * .pi / 180, kLon = 39.8262 * .pi / 180
        let y = sin(kLon - lon)
        let x = cos(lat) * tan(kLat) - sin(lat) * cos(kLon - lon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

#if DEBUG
/// The compass's own log on the phone (DEBUG builds): a line a second while the app is on screen,
/// plus restarts and status changes, in the app's Library/Caches/compass.log (the last ~1 MB; the
/// one before is compass.old.log). Pull it with
/// `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer
///  --domain-identifier com.betternorms.shukr --source Library/Caches/compass.log --destination <file>`.
enum CompassLog {
    private static let queue = DispatchQueue(label: "shukr.compassLog", qos: .utility)
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "compass.log")
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    static func write(_ line: String) {
        let text = "\(stamp.string(from: Date())) \(line)\n"
        queue.async {
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1_000_000 {
                let old = url.deletingLastPathComponent().appending(path: "compass.old.log")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            guard let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
#endif
