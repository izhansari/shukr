//
//  WatchQiblaMap.swift
//  shukrWatch
//
//  The phone's qibla map, on the wrist (owner, 2026-10-06: "clicking the Qibla arrow … renders the map with you
//  facing towards the Qibla. So the Qibla is always facing up … that green line … that pill at the top that tells us
//  turn right, turn left, facing Makkah … it colors that circle green"; no Explore, prayers or mosques). Ported from
//  LocationMapView2.swift: the camera swings Qibla-up 0.35 s after it opens (`pointQiblaUp`), the geodesic line to the
//  Kaaba (systemGreen 90 %, 3 pt, round), the turn pill, the ring on the dot (`CircleWithArrowOverlay`: white ring,
//  the green turn arc, the qibla triangle, the heading chevron — green and thicker once aligned), the edge glow and a
//  buzz each second while aligned. Rules from the phone's CompassState: off = bearing − heading (−180…180, + = turn
//  right), aligned within the phone's qibla accuracy, let go 1.5° past it.
//

import SwiftUI
import MapKit
import WatchKit

struct WatchQiblaMap: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var compass = WatchCompass.shared
    @Environment(\.isLuminanceReduced) private var wristDown
    @State private var position: MapCameraPosition = .automatic
    @State private var mapHeading: Double = 0
    @State private var aligned = false
    /// Where the line starts: the watch's own fix if it has a recent one, else where the phone last was.
    private let here: CLLocationCoordinate2D?

    /// About the phone's `qiblaSpan` (0.002°, ~220 m across a phone) on a watch's narrower screen.
    private static let distance: CLLocationDistance = 600
    private static let kaaba = CLLocationCoordinate2D(latitude: WatchQibla.kaaba.lat, longitude: WatchQibla.kaaba.lon)

    init() {
        if let own = WatchCompass.shared.recentLocation {
            here = CLLocationCoordinate2D(latitude: own.lat, longitude: own.lon)
        } else if WatchStore.hasLocation {
            let d = WatchStore.defaults
            here = CLLocationCoordinate2D(latitude: d.double(forKey: WatchStore.Key.latitude),
                                          longitude: d.double(forKey: WatchStore.Key.longitude))
        } else {
            here = nil
        }
    }

    private var bearing: Double? { here.map { WatchQibla.bearing(fromLat: $0.latitude, lon: $0.longitude) } }

    /// Degrees to turn: + right (clockwise), − left.
    private var off: Double? {
        guard let bearing, let heading = compass.heading else { return nil }
        return WatchQibla.signed(bearing - heading)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let here, let bearing {
                    map(here: here, bearing: bearing)
                } else {
                    Text("Open shukr on your iPhone so the watch knows where you are.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .onAppear { compass.start(); updateAligned() }
        .onDisappear { compass.stop() }
        .onChange(of: compass.heading) { _, _ in updateAligned() }
        // A buzz each second while you face it (the phone's heavy one; the watch's strongest single tap).
        .task(id: aligned && !wristDown) {
            guard aligned, !wristDown else { return }
            while !Task.isCancelled {
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func map(here: CLLocationCoordinate2D, bearing: Double) -> some View {
        Map(position: $position, interactionModes: [.zoom, .pan]) {
            MapPolyline(coordinates: [here, Self.kaaba], contourStyle: .geodesic)
                .stroke(Color.green.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            Annotation("Kaaba", coordinate: Self.kaaba) {
                Text("🕋").font(.system(size: 18))
            }
            .annotationTitles(.hidden)
            Annotation("You", coordinate: here, anchor: .center) {
                WatchQiblaRing(off: off, bearing: bearing, mapHeading: mapHeading, aligned: aligned)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard)
        .mapControlVisibility(.hidden)
        .onMapCameraChange(frequency: .continuous) { context in mapHeading = context.camera.heading }
        .ignoresSafeArea()
        .overlay(alignment: .top) { pill }
        .overlay {
            // The phone's AlignedEdgeGlow: the screen's edge goes green while you face it.
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .stroke(Color.green.opacity(0.85), lineWidth: 10)
                .blur(radius: 8)
                .ignoresSafeArea()
                .opacity(aligned ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: aligned)
                .allowsHitTesting(false)
        }
        .onAppear {
            position = .camera(MapCamera(centerCoordinate: Self.ahead(of: here, toward: 0), distance: Self.distance,
                                         heading: 0, pitch: 0))
            // The phone's swing: north first, then Qibla-up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeInOut(duration: 0.9)) {
                    position = .camera(MapCamera(centerCoordinate: Self.ahead(of: here, toward: bearing),
                                                 distance: Self.distance, heading: bearing, pitch: 0))
                }
            }
        }
    }

    /// The camera looks a little ahead of you, up the screen, so your dot sits below the middle and the pill at the top
    /// never covers the ring or its qibla triangle (the map's own padding doesn't move its centre once it fills the
    /// screen).
    private static func ahead(of p: CLLocationCoordinate2D, toward bearing: Double) -> CLLocationCoordinate2D {
        let metres = distance * 0.07
        let b = bearing * .pi / 180
        return CLLocationCoordinate2D(latitude: p.latitude + metres * cos(b) / 111_320,
                                      longitude: p.longitude + metres * sin(b) / (111_320 * cos(p.latitude * .pi / 180)))
    }

    /// "← Turn left 23°" / "Turn right 23° →" / "Facing Mecca 🕋" — the phone's words.
    private var pill: some View {
        Group {
            if let off {
                let degrees = Int(abs(off).rounded())
                Text(aligned ? "Facing Mecca 🕋" : off < 0 ? "← Turn left \(degrees)°" : "Turn right \(degrees)° →")
            } else {
                Text(compass.available ? "Finding north…" : "No compass")
            }
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(aligned ? Color.green : Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.green, lineWidth: 1.5).opacity(aligned ? 1 : 0))
        .animation(.easeInOut(duration: 0.2), value: aligned)
        .padding(.top, 2)
    }

    private func updateAligned() {
        guard let off else { if aligned { aligned = false }; return }
        let s = WatchQibla.sensitivity
        let now = abs(off) <= (aligned ? s + 1.5 : s)
        guard now != aligned else { return }
        aligned = now
        if now { WKInterfaceDevice.current().play(.success) }
    }
}

/// The phone's CircleWithArrowOverlay round the dot, scaled to the watch: a white ring (green and thicker once
/// aligned), the green arc from where you face to the qibla, the qibla's triangle on the ring, and the chevron for where
/// you face. Angles are on screen: a compass angle minus the map's own heading.
struct WatchQiblaRing: View {
    let off: Double?
    let bearing: Double
    let mapHeading: Double
    let aligned: Bool
    private let size: CGFloat = 110

    var body: some View {
        let heading = off.map { bearing - $0 }
        ZStack {
            // You: the system's blue location dot.
            Circle()
                .fill(Color.blue)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 2)
            Circle()
                .stroke(aligned ? Color.green : Color.white, lineWidth: aligned ? 3.5 : 2)
                .shadow(color: aligned ? Color.white.opacity(0.7) : Color.black.opacity(0.15), radius: aligned ? 8 : 2)
            if let off, let heading, !aligned {
                // The turn: clockwise from where you face when it's to your right, from the qibla when to your left.
                let start = off >= 0 ? heading : bearing
                Circle()
                    .trim(from: 0, to: min(abs(off), 359) / 360)
                    .stroke(Color.green.opacity(0.85), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(start - mapHeading - 90))
            }
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 13))
                .foregroundStyle(aligned ? Color.green : Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1)
                .offset(y: -size / 2 - 9)
                .rotationEffect(.degrees(bearing - mapHeading))
            if let heading {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(aligned ? Color.green : Color.blue)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(y: -14)
                    .rotationEffect(.degrees((aligned ? bearing : heading) - mapHeading))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: aligned)
            }
        }
        .frame(width: size, height: size)
        .animation(.default, value: aligned)
        .allowsHitTesting(false)
    }
}
