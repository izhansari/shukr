//
//  MapModes.swift
//  shukr
//
//  "Map Modes", like Apple Maps' own sheet (2026-09-27, notes #15): a globe button in the map's
//  controls opens a short glass sheet — ✕, "Map Modes", two picture cards (Standard / Satellite,
//  a blue edge on the chosen one), and a grouped card with Traffic and (for Satellite) Labels.
//  The pictures are live snapshots of the user's own spot in each style, not Apple's artwork.
//  MapKit: Standard = MKStandardMapConfiguration; Satellite + Labels = MKHybridMapConfiguration;
//  Satellite without labels = MKImageryMapConfiguration; Traffic = showsTraffic. Remembered in
//  @AppStorage. No 3D button (the qibla line reads best flat).
//  One sheet at a time: it opens *over* an open prayer / mosque sheet (each presents it from its
//  own content) rather than closing it first — closing, then opening, then reopening read as three
//  animations and lost your place.
//

import SwiftUI
import MapKit

enum MapModes {
    static let satelliteKey = "mapMode.satellite"
    static let trafficKey = "mapMode.traffic"
    static let labelsKey = "mapMode.labels"

    static func configuration(satellite: Bool, traffic: Bool, labels: Bool) -> MKMapConfiguration {
        if satellite {
            if labels {
                let c = MKHybridMapConfiguration()
                c.showsTraffic = traffic
                return c
            }
            return MKImageryMapConfiguration()
        }
        let c = MKStandardMapConfiguration()
        c.showsTraffic = traffic
        return c
    }

    /// Apple swaps the globe by region; we go by where the user is.
    static func globeSymbol(longitude: Double?) -> String {
        guard let lon = longitude else { return "globe.americas.fill" }
        if lon < -25 { return "globe.americas.fill" }
        if lon < 65 { return "globe.europe.africa.fill" }
        return "globe.asia.australia.fill"
    }
}

/// The sheet.
struct MapModesSheet: View {
    /// Where the preview snapshots are taken: the user's spot (or the map's centre).
    let centre: CLLocationCoordinate2D
    var close: () -> Void

    @AppStorage(MapModes.satelliteKey) private var satellite = false
    @AppStorage(MapModes.trafficKey) private var traffic = false
    @AppStorage(MapModes.labelsKey) private var labels = true
    @Environment(\.colorScheme) private var scheme
    @State private var standardShot: UIImage?
    @State private var satelliteShot: UIImage?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Text("Map Modes")
                    .font(.headline)
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .mapGlass(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                }
            }

            HStack(spacing: 14) {
                card("Standard", image: standardShot, selected: !satellite) { satellite = false }
                card("Satellite", image: satelliteShot, selected: satellite) { satellite = true }
            }

            VStack(spacing: 0) {
                Toggle("Traffic", isOn: $traffic)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                if satellite {
                    Divider().padding(.leading, 16)
                    Toggle("Labels", isOn: $labels)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .transition(.opacity)
                }
            }
            .tint(.green)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.06)))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .animation(.snappy, value: satellite)
        .sensoryFeedback(.selection, trigger: satellite)
        .presentationDetents([.height(satellite ? 376 : 326)])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled)
        .task(id: scheme) { await loadSnapshots() }
    }

    private func card(_ title: String, image: UIImage?, selected: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.08))
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(height: 104 * 150 / 110, alignment: .top)
                            .frame(height: 104, alignment: .top)
                            .clipped()
                            .transition(.opacity)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(selected ? Color.blue : .clear, lineWidth: 3))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Two small live snapshots of the user's spot, one per style.
    private func loadSnapshots() async {
        async let standard = snapshot(MKStandardMapConfiguration())
        async let imagery = snapshot(MKImageryMapConfiguration())
        let (s, i) = await (standard, imagery)
        withAnimation(.easeOut(duration: 0.25)) {
            standardShot = s
            satelliteShot = i
        }
    }

    private func snapshot(_ configuration: MKMapConfiguration) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: centre, latitudinalMeters: 450, longitudinalMeters: 450)
        // Taller than the card, cropped from the top: the Maps logo in the bottom corner stays out.
        options.size = CGSize(width: 180, height: 150)
        options.preferredConfiguration = configuration
        options.traitCollection = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        return try? await MKMapSnapshotter(options: options).start().image
    }
}

extension View {
    /// Presents the Map Modes sheet from this view (the map itself, or an open prayer / mosque
    /// sheet, so it opens over that one).
    func mapModesSheet(isPresented: Binding<Bool>, centre: @escaping () -> CLLocationCoordinate2D) -> some View {
        sheet(isPresented: isPresented) {
            MapModesSheet(centre: centre()) { isPresented.wrappedValue = false }
        }
    }
}
