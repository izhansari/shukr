//
//  PrayerLocationPicker.swift
//  shukr
//
//  "Where did you pray?" (owner, 2026-09-26: a prayer's spot couldn't be changed anywhere). A map
//  with a pin fixed in the middle: drag the map until the pin sits where you prayed, then Set
//  location. The pin lifts while the map moves and drops when it stops; the address (or one of
//  your masajid, if the pin is on one) updates under it. Where it was before shows as a small gray
//  dot. Opened from the time editor (long-press a prayed prayer) and from a prayer in the map's
//  prayer-spot sheet. Moving a prayer re-checks whether it was at a masjid
//  (`PrayerViewModel.movePrayer`), so a Friday Dhuhr can become Jumu'ah — or stop being one.
//

import SwiftUI
import MapKit

struct PrayerLocationPicker: View {
    let prayerName: String
    /// Where the prayer is pinned now (nil = nowhere yet: the map opens on you).
    let original: CLLocationCoordinate2D?
    var onCancel: () -> Void
    var onPick: (CLLocationCoordinate2D) -> Void

    @State private var camera: MapCameraPosition
    @State private var centre: CLLocationCoordinate2D?
    @State private var moving = false
    @State private var address: String?
    @State private var lookup: Task<Void, Never>?

    init(prayerName: String, original: CLLocationCoordinate2D?,
         onCancel: @escaping () -> Void, onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.prayerName = prayerName
        self.original = original
        self.onCancel = onCancel
        self.onPick = onPick
        _camera = State(initialValue: original.map {
            .region(MKCoordinateRegion(center: $0, latitudinalMeters: 350, longitudinalMeters: 350))
        } ?? .userLocation(fallback: .automatic))
        _centre = State(initialValue: original)
    }

    /// One of your masajid under the pin (the same 100 m the masjid check uses).
    private var masjid: String? { centre.flatMap { MasjidDetector.favoriteMasjid(near: $0) } }

    private var changed: Bool {
        guard let centre else { return false }
        guard let original else { return true }
        return CLLocation(latitude: centre.latitude, longitude: centre.longitude)
            .distance(from: CLLocation(latitude: original.latitude, longitude: original.longitude)) > 3
    }

    var body: some View {
        ZStack {
            Map(position: $camera) {
                UserAnnotation()
                if let original {
                    // Where it was pinned before.
                    Annotation("", coordinate: original, anchor: .center) {
                        Circle().fill(Color.gray.opacity(0.7)).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                ForEach(MosqueFavorites.all, id: \.id) { m in
                    Marker(m.name, systemImage: "star.fill",
                           coordinate: CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude))
                        .tint(.green)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange(frequency: .continuous) { ctx in
                centre = ctx.region.center
                if !moving { withAnimation(.snappy(duration: 0.15)) { moving = true } }
            }
            .onMapCameraChange(frequency: .onEnd) { ctx in
                centre = ctx.region.center
                withAnimation(.spring(duration: 0.3, bounce: 0.45)) { moving = false }
                lookUp(ctx.region.center)
            }

            // The pin, fixed in the middle; its tip is the spot.
            ZStack {
                Ellipse()
                    .fill(.black.opacity(moving ? 0.12 : 0.25))
                    .frame(width: moving ? 8 : 12, height: moving ? 3 : 5)
                Image(systemName: "mappin")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundStyle(Color.green)
                    .shadow(color: .black.opacity(0.25), radius: moving ? 6 : 2, y: moving ? 6 : 1)
                    .offset(y: moving ? -30 : -20)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .top) {
            Text("Where did you pray \(prayerName)?")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .mapGlass(Capsule())
                .padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) { card }
        .fontDesign(.rounded)
        .onAppear { if let original { lookUp(original) } }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: masjid != nil ? "building.columns" : "mappin.and.ellipse")
                    .foregroundStyle(masjid != nil ? Color.sage : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(masjid ?? address ?? (centre == nil ? "Finding you…" : "Looking up the address…"))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if masjid != nil, let address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .opacity(moving ? 0.4 : 1)   // the last address, until the pin drops
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: address)
            }
            Text("Drag the map to put the pin where you prayed.")
                .font(.footnote)
                .fontWeight(.light)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.primary)
                        .background(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                        .contentShape(Capsule())
                }
                Button {
                    if let centre { onPick(centre) }
                } label: {
                    // Same Save look as the time editor: gray until there's a change.
                    Text("Set location")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(changed ? Color.green : Color.secondary)
                        .background(Capsule().strokeBorder(changed ? Color.green : Color(.separator),
                                                           lineWidth: changed ? 1.5 : 1))
                        .contentShape(Capsule())
                }
                .disabled(!changed)
                .animation(.easeInOut(duration: 0.2), value: changed)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 28)
    }

    /// Street + city under the pin, once the map settles (a new drag cancels the last lookup).
    private func lookUp(_ c: CLLocationCoordinate2D) {
        lookup?.cancel()
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let placemark = try? await CLGeocoder()
                .reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
            guard !Task.isCancelled else { return }
            let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let place = [street.isEmpty ? placemark?.name : street, placemark?.locality]
                .compactMap { $0 }.joined(separator: ", ")
            address = place.isEmpty ? nil : place
        }
    }
}

/// "123 Main St, Cary" for a spot — for the time editor's location row.
enum PrayerSpotAddress {
    private static var cache: [String: String] = [:]
    static func lookUp(_ c: CLLocationCoordinate2D) async -> String? {
        let key = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        if let hit = cache[key] { return hit }
        let placemark = try? await CLGeocoder()
            .reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let place = [street.isEmpty ? placemark?.name : street, placemark?.locality]
            .compactMap { $0 }.joined(separator: ", ")
        guard !place.isEmpty else { return nil }
        cache[key] = place
        return place
    }
}
