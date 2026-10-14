//
//  ExploreGroupPictures.swift
//  shukr
//
//  A section's own picture on Explore (owner: not one of its items again, and something familiar): the phone on its Home
//  Screen, Lock Screen or Control Center with shukr's pieces in place, the Shortcuts app's shukr tiles, a watch face, the
//  map, prayer beads. Drawn at the real sizes (a 393 pt phone, the real widgets and controls), then scaled. A section with
//  one item keeps that item's picture.
//

import SwiftUI
import WidgetKit
import AppIntents

/// A section's picture: its own scene when it has several items, else its one item's picture.
struct ExploreSectionPicture: View {
    let group: ExploreGroupID
    var big = false
    var scale: CGFloat? = nil
    var phone: CGFloat = 0.44
    var body: some View {
        if group.members.count > 1 { ExploreGroupPicture(group: group, scale: phone) }
        else { ShowcasePicture(id: group.picture, big: big, scale: scale) }
    }
}

struct ExploreGroupPicture: View {
    let group: ExploreGroupID
    /// The phone's scale (it runs off the panel's foot).
    var scale: CGFloat = 0.44
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        panel.overlay(alignment: .top) {
            picture
        }
        .clipped()
        .allowsHitTesting(false)
    }

    private var panel: some View {
        LinearGradient(colors: scheme == .dark ? [Color(red: 0.17, green: 0.33, blue: 0.25), Color(red: 0.07, green: 0.10, blue: 0.08)]
                                               : [Color(red: 0.85, green: 0.92, blue: 0.87), Color(red: 0.93, green: 0.96, blue: 0.94)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder private var picture: some View {
        switch group {
        case .homeWidgets: phone { HomeScreenScene() }
        case .lockWidgets: phone { LockScreenScene() }
        case .controls: phone { ControlCenterScene() }
        case .siri:
            // The Shortcuts app's own icon, in Apple's button (owner: "show the shortcuts icon so people are familiar").
            HStack(alignment: .top, spacing: 14) {
                ShortcutsLink().shortcutsLinkStyle(.light)
                    .fixedSize()
                    .scaleEffect(0.7 * scale / 0.5)
                    .frame(width: 112 * scale / 0.5, height: 44 * scale / 0.5)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .padding(.top, 60 * scale / 0.5)
                phone { ShortcutsScene() }
            }
        case .mapMasjid: phone { MapScene() }
        case .watch:
            RealWatch { WatchFaceScene() }
                .scaleEffect(scale * 1.35, anchor: .top)
                .padding(.top, 14)
        case .zikrExtras:
            Beads().frame(maxHeight: .infinity)
        default: EmptyView()
        }
    }

    private func phone<Screen: View>(@ViewBuilder _ screen: @escaping () -> Screen) -> some View {
        ExplorePhone(screen: screen)
            .scaleEffect(scale, anchor: .top)
            .frame(width: phoneSize.width * scale, height: phoneSize.height * scale, alignment: .top)
            .padding(.top, 16)
    }
}

/// An iPhone, its screen whatever's given, the status bar on top.
private let phoneSize = CGSize(width: 393 + 24, height: 852 + 24)

struct ExplorePhone<Screen: View>: View {
    var darkStatus = true
    @ViewBuilder let screen: () -> Screen
    var body: some View {
        screen()
            .frame(width: 393, height: 852, alignment: .top)
            .overlay(alignment: .top) { statusBar }
            .clipShape(RoundedRectangle(cornerRadius: 55, style: .continuous))
            .overlay(alignment: .top) { Capsule().fill(.black).frame(width: 125, height: 37).padding(.top, 11) }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 67, style: .continuous).fill(Color(white: 0.12)))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .environment(\.colorScheme, .dark)
    }
    private var statusBar: some View {
        HStack {
            Text(ExplorePreset.clockFace).font(.system(size: 17, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "cellularbars"); Image(systemName: "wifi"); Image(systemName: "battery.100")
            }
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 34).padding(.top, 18)
    }
}

// MARK: - The scenes (393 × 852)

/// A Home Screen: shukr's Prayers and Zikr widgets in the top row, apps under them.
private struct HomeScreenScene: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.23, green: 0.36, blue: 0.33), Color(red: 0.10, green: 0.16, blue: 0.20)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 26) {
                HStack(spacing: 22) {
                    labelled(RealPrayersWidget())
                    labelled(RealZikrWidget(family: .systemSmall).environment(\.colorScheme, .dark))
                }
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 27) { ForEach(0..<4, id: \.self) { AppIcon(index: row * 4 + $0) } }
                }
            }
            .padding(.top, 70)
        }
    }
    private func labelled<V: View>(_ widget: V) -> some View {
        VStack(spacing: 6) {
            widget
            Text("shukr").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// A plain app on the Home Screen: a tinted square, no one's real icon.
private struct AppIcon: View {
    let index: Int
    private static let tints: [Color] = [.init(red: 0.36, green: 0.55, blue: 0.82), .init(red: 0.91, green: 0.62, blue: 0.32),
                                         .init(red: 0.45, green: 0.70, blue: 0.52), .init(red: 0.62, green: 0.50, blue: 0.80),
                                         .init(red: 0.85, green: 0.45, blue: 0.48), .init(red: 0.40, green: 0.64, blue: 0.72),
                                         .init(red: 0.78, green: 0.72, blue: 0.40), .init(red: 0.55, green: 0.58, blue: 0.62)]
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Self.tints[index % 8].opacity(0.95), Self.tints[index % 8].opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .frame(width: 62, height: 62)
            Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 6)
        }
    }
}

/// A Lock Screen: today's Name on the line above the clock, the Prayers widget's circle and countdown under it.
private struct LockScreenScene: View {
    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [Color(red: 0.25, green: 0.33, blue: 0.42), Color(red: 0.06, green: 0.08, blue: 0.10)],
                           center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 700)
            VStack(spacing: 4) {
                NameOfTheDayView(entry: NameOfTheDayEntry(date: ExplorePreset.now, name: NamesOfAllah.nameOfTheDay()), familyOverride: .accessoryInline)
                    .frame(width: 300, height: 22)
                    .font(.system(size: 17, weight: .semibold))
                Text(ExplorePreset.clockFace)
                    .font(.system(size: 104, weight: .semibold, design: .rounded))
                    .lineLimit(1).fixedSize()
                HStack(spacing: 12) {
                    RealLockWidget(family: .accessoryCircular)
                    RealLockWidget(family: .accessoryRectangular)
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(.top, 72)
        }
    }
}

/// Control Center: the phone's own controls, then shukr's five in a row of their own.
private struct ControlCenterScene: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.24), Color(red: 0.08, green: 0.09, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    connectivity.gridCellColumns(2)
                    module { VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "music.note").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        Text("Not Playing").font(.system(size: 12, weight: .semibold)).opacity(0.7)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14) }
                    .gridCellColumns(2)
                }
                GridRow {
                    CCPill(ControlFaces.prayer).gridCellColumns(2)
                    CCCircle(symbol: ControlFaces.prayed.symbol)
                    CCCircle(symbol: ControlFaces.qibla.symbol)
                }
                GridRow {
                    CCPill(ControlFaces.fajr).gridCellColumns(2)
                    CCCircle(symbol: ControlFaces.zikr.symbol)
                    CCCircle(symbol: "flashlight.off.fill")
                }
            }
            .scaleEffect(1.25, anchor: .top)
            .padding(.top, 84)
        }
    }
    private var connectivity: some View {
        module {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow { dot("airplane", .orange, on: false); dot("antenna.radiowaves.left.and.right", .green, on: true) }
                GridRow { dot("wifi", .blue, on: true); dot("personalhotspot", .green, on: false) }
            }
        }
    }
    private func dot(_ symbol: String, _ tint: Color, on: Bool) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(Circle().fill(on ? tint : .white.opacity(0.18)))
    }
    private func module<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(width: 124, height: 124)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white.opacity(0.14)))
    }
}

/// The Shortcuts app on shukr's page: its tiles, in the tile colour shukr asks for (`shortcutTileColor`, grey-green).
private struct ShortcutsScene: View {
    private let tiles: [(String, String)] = [("hourglass", "Time Left"), ("list.bullet", "Today’s Times"),
                                             ("checkmark.circle", "I Prayed"), ("building.columns", "Nearby Mosques"),
                                             ("checklist", "Zikr Tasks"), ("alarm", "Fajr Alarm Time")]
    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                    Text("Shortcuts").font(.system(size: 17))
                }
                .foregroundStyle(Color(red: 0.36, green: 0.55, blue: 1))
                Text("shukr").font(.system(size: 34, weight: .bold))
                LazyVGrid(columns: [GridItem(.fixed(166), spacing: 14), GridItem(.fixed(166))], spacing: 14) {
                    ForEach(tiles, id: \.1) { tile($0.0, $0.1) }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.top, 64)
        }
    }
    private func tile(_ symbol: String, _ name: String) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
                Spacer()
                Image(systemName: "ellipsis.circle.fill").font(.system(size: 20)).opacity(0.5)
            }
            Spacer()
            Text(name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
        }
        .padding(14)
        .frame(width: 166, height: 104)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.47, green: 0.58, blue: 0.53), Color(red: 0.36, green: 0.47, blue: 0.43)],
                                 startPoint: .top, endPoint: .bottom)))
    }
}

/// The map: prayers pinned where they were prayed (in their grade colours), the masjid, you, and the masjid's card.
private struct MapScene: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.17, green: 0.18, blue: 0.20)))
                ctx.fill(Path(roundedRect: CGRect(x: 30, y: 300, width: 150, height: 110), cornerRadius: 30), with: .color(Color(red: 0.18, green: 0.25, blue: 0.20)))
                ctx.fill(Path(roundedRect: CGRect(x: 250, y: 120, width: 120, height: 90), cornerRadius: 26), with: .color(Color(red: 0.18, green: 0.25, blue: 0.20)))
                var water = Path()
                water.move(to: CGPoint(x: 393, y: 420)); water.addCurve(to: CGPoint(x: 300, y: 560), control1: CGPoint(x: 330, y: 450), control2: CGPoint(x: 290, y: 500))
                water.addLine(to: CGPoint(x: 393, y: 600)); water.closeSubpath()
                ctx.fill(water, with: .color(Color(red: 0.12, green: 0.20, blue: 0.29)))
                func road(_ pts: [CGPoint], _ w: CGFloat, _ c: Color) {
                    var p = Path(); p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
                    ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                }
                let street = Color(white: 0.30)
                road([CGPoint(x: 0, y: 250), CGPoint(x: 393, y: 220)], 8, street)
                road([CGPoint(x: 0, y: 440), CGPoint(x: 393, y: 470)], 8, street)
                road([CGPoint(x: 120, y: 0), CGPoint(x: 140, y: 852)], 8, street)
                road([CGPoint(x: 260, y: 0), CGPoint(x: 240, y: 852)], 6, street)
                road([CGPoint(x: 0, y: 620), CGPoint(x: 200, y: 330), CGPoint(x: 393, y: 90)], 12, Color(red: 0.42, green: 0.38, blue: 0.27))
            }
            pin(.green, at: CGPoint(x: 90, y: 200))
            pin(.green, at: CGPoint(x: 310, y: 330))
            pin(.yellow, at: CGPoint(x: 200, y: 400))
            pin(.green, at: CGPoint(x: 60, y: 520))
            Image(systemName: "building.columns.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 40, height: 40).background(Circle().fill(Color.sage)).overlay(Circle().stroke(.white, lineWidth: 3))
                .position(x: 190, y: 285)
            Circle().fill(Color.blue).frame(width: 20, height: 20).overlay(Circle().stroke(.white, lineWidth: 4)).position(x: 270, y: 380)
            VStack(alignment: .leading, spacing: 3) {
                Text(ExplorePreset.masjid).font(.system(size: 17, weight: .semibold))
                Text("4 min drive · 1.2 mi").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.16)))
            .position(x: 190, y: 220)
        }
    }
    private func pin(_ color: Color, at point: CGPoint) -> some View {
        Circle().fill(color).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 3)).position(point)
    }
}

/// A watch face: the time, shukr's prayer card across the middle and its ring among the corners.
private struct WatchFaceScene: View {
    var body: some View {
        let p = ShownPrayer.now
        let entry = PrayerComplicationEntry(date: ExplorePreset.now, prayer: WatchPrayer(name: p.name, start: p.start, end: p.end), current: p.isOn)
        VStack(alignment: .leading, spacing: 12) {
            Text(ExplorePreset.clockFace).font(.system(size: 52, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
            PrayerComplicationView(entry: entry, familyOverride: .accessoryRectangular)
                .frame(height: 60, alignment: .leading)
            HStack(spacing: 10) {
                PrayerComplicationView(entry: entry, familyOverride: .accessoryCircular).frame(width: 52, height: 52)
                Circle().fill(Color(white: 0.14)).frame(width: 52, height: 52)
                    .overlay(Image(systemName: "cloud.sun.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.6)))
                Circle().fill(Color(white: 0.14)).frame(width: 52, height: 52)
                    .overlay(Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(.red.opacity(0.7)))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// Prayer beads: 33 round the loop, the larger one at its foot, the tassel.
private struct Beads: View {
    var body: some View {
        ZStack {
            ForEach(0..<33, id: \.self) { i in
                let a = Angle.degrees(Double(i) / 33 * 360 + 90 + 360 / 66)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.62, green: 0.80, blue: 0.68), Color.sage], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
                    .frame(width: 12, height: 12)
                    .offset(x: 52 * cos(a.radians), y: 52 * sin(a.radians))
            }
            Capsule().fill(Color.sage).frame(width: 18, height: 22).offset(y: 58)
            Capsule().fill(Color.sage.opacity(0.8)).frame(width: 4, height: 26).offset(y: 80)
            VStack(spacing: 0) {
                Text("33").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("zikr").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .offset(y: -8)
    }
}
