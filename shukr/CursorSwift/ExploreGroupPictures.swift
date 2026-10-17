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
        case .lockWidgets: phone { LockScreenScene(show: [.lockTime, .lockCountdown, .lockName]) }
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
        case .mapMasjid: phone { PrayerPinsScene(sheet: false) }   // the app's map, as the items show it
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

/// One Lock Screen item on a phone's Lock Screen (owner: "how it would look on the phone lock screen").
struct ExploreLockPicture: View {
    let id: ShowcaseCardID
    var scale: CGFloat = 0.55
    var body: some View {
        ExplorePhone { LockScreenScene(show: [id]) }
            .scaleEffect(scale, anchor: .top)
            .frame(width: phoneSize.width * scale, height: phoneSize.height * scale, alignment: .top)
            .padding(.top, 16)
            .allowsHitTesting(false)
    }
}

/// A Lock Screen: today's Name on the line above the clock (else the date, as iOS has it), the Prayers widget's circle
/// and countdown under it — whichever of them `show` holds.
private struct LockScreenScene: View {
    var show: Set<ShowcaseCardID>
    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [Color(red: 0.25, green: 0.33, blue: 0.42), Color(red: 0.06, green: 0.08, blue: 0.10)],
                           center: UnitPoint(x: 0.3, y: 0.1), startRadius: 0, endRadius: 700)
            VStack(spacing: 4) {
                Group {
                    if show.contains(.lockName) {
                        NameOfTheDayView(entry: NameOfTheDayEntry(date: ExplorePreset.now, name: NamesOfAllah.nameOfTheDay()), familyOverride: .accessoryInline)
                    } else {
                        Text(ExplorePreset.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    }
                }
                .frame(width: 340, height: 22)
                .font(.system(size: 17, weight: .semibold))
                LockDemoClock()
                    .font(.system(size: 104, weight: .semibold, design: .rounded))
                    .lineLimit(1).fixedSize()
                HStack(spacing: 12) {
                    if show.contains(.lockTime) { RealLockWidget(family: .accessoryCircular) }
                    if show.contains(.lockCountdown) { RealLockWidget(family: .accessoryRectangular) }
                }
                .padding(.top, 6)
            }
            .foregroundStyle(.white)
            .padding(.top, 72)
        }
        // The widgets' states in turn, the clock with them — only with a prayer widget on it (the Name's alone: still).
        .playsLockStates(show.contains(.lockTime) || show.contains(.lockCountdown))
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

// MARK: - The map items and the notification, each on the phone (owner: "look like our actual app's map")

/// An item's picture on the phone, as the Lock Screen items have (ExploreLockPicture): the notification held open on a
/// Lock Screen, the map with its prayer pins and sheet, the mosque finder, a Friday's list with Jumu'ah.
struct ExploreItemPhonePicture: View {
    let id: ShowcaseCardID
    var scale: CGFloat = 0.55
    static let ids: Set<ShowcaseCardID> = [.answer, .prayersMap, .mosques, .jumuah]
    var body: some View {
        // A little smaller than the Lock Screen ones: more of the screen fits in the panel.
        let scale = scale * 0.8
        ExplorePhone { scene }
            .offset(y: -lift)
            .scaleEffect(scale, anchor: .top)
            .frame(width: phoneSize.width * scale, height: phoneSize.height * scale, alignment: .top)
            .padding(.top, 16)
            .allowsHitTesting(false)
    }
    /// How far up the phone sits in its panel, so the part that matters shows (the panel only holds the phone's top):
    /// the held reminder, the map's pins and sheet, the circle and the list.
    private var lift: CGFloat {
        switch id {
        case .answer: 0
        case .prayersMap, .mosques: 300
        default: 110
        }
    }
    @ViewBuilder private var scene: some View {
        switch id {
        case .answer: NotificationScene()
        case .prayersMap: PrayerPinsScene()
        case .mosques: MosqueFinderScene()
        default: JumuahScene()
        }
    }
}

/// A prayer's reminder at the top of the phone, pulled down to its buttons (owner: "the notification at the top of the
/// phone"), the Home Screen dimmed behind it.
private struct NotificationScene: View {
    var body: some View {
        ZStack(alignment: .top) {
            HomeScreenScene()
            Color.black.opacity(0.5)
            RealNotification()
                .scaleEffect(1.12, anchor: .top)
                .padding(.top, 58)
        }
    }
}

/// The map's ground: blocks, parks, water and streets, in Apple Maps' dark look (as the app's map shows at night).
private struct MapGround: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.17, green: 0.18, blue: 0.20)))
            for r in [CGRect(x: 30, y: 300, width: 150, height: 110), CGRect(x: 250, y: 120, width: 120, height: 90),
                      CGRect(x: 280, y: 600, width: 100, height: 120)] {
                ctx.fill(Path(roundedRect: r, cornerRadius: 26), with: .color(Color(red: 0.18, green: 0.25, blue: 0.20)))
            }
            var water = Path()
            water.move(to: CGPoint(x: 393, y: 420)); water.addCurve(to: CGPoint(x: 300, y: 560), control1: CGPoint(x: 330, y: 450), control2: CGPoint(x: 290, y: 500))
            water.addLine(to: CGPoint(x: 393, y: 600)); water.closeSubpath()
            ctx.fill(water, with: .color(Color(red: 0.12, green: 0.20, blue: 0.29)))
            func road(_ pts: [CGPoint], _ w: CGFloat, _ c: Color) {
                var p = Path(); p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
                ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            let street = Color(white: 0.30)
            for y in [130.0, 250, 440, 560, 700] { road([CGPoint(x: 0, y: y), CGPoint(x: 393, y: y - 25)], 6, street) }
            for x in [40.0, 140, 260, 350] { road([CGPoint(x: x, y: 0), CGPoint(x: x + 20, y: 852)], 6, street) }
            road([CGPoint(x: 0, y: 620), CGPoint(x: 200, y: 330), CGPoint(x: 393, y: 90)], 12, Color(red: 0.42, green: 0.38, blue: 0.27))
        }
    }
}

/// A pin as the app's map draws it (MKMarkerAnnotationView): a round balloon in the pin's colour, its white glyph, the
/// little point under it; a cluster shows its count.
private struct MapBalloon: View {
    let color: Color
    var symbol: String? = nil
    var count: Int? = nil
    var big = false
    var body: some View {
        let d: CGFloat = big ? 44 : 34
        VStack(spacing: -3) {
            ZStack {
                Circle().fill(color)
                if let count {
                    Text("\(count)").font(.system(size: d * 0.42, weight: .bold)).foregroundStyle(.white)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: d * 0.42, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: d, height: d)
            Triangle().fill(color).frame(width: 10, height: 7)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }
    private struct Triangle: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath() }
        }
    }
}

/// The map's own chrome: ⌄ on the left, the status pill in the middle, the globe / locate / Explore column on the right.
private struct MapChrome: View {
    let status: String
    let explore: String
    var body: some View {
        VStack {
            HStack(alignment: .top) {
                glass(Image(systemName: "chevron.down"))
                Spacer()
                Text(status).font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding(.horizontal, 18).frame(height: 46)
                    .background(Capsule().fill(.white.opacity(0.14)))
                Spacer()
                VStack(spacing: 10) {
                    VStack(spacing: 18) {
                        Image(systemName: "globe.americas.fill"); Image(systemName: "location.fill")
                    }
                    .padding(.vertical, 14).frame(width: 46)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    glass(Image(systemName: explore)).foregroundStyle(Color.sage)
                }
            }
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.top, 62)
            Spacer()
        }
    }
    private func glass(_ image: Image) -> some View {
        image.frame(width: 46, height: 46).background(Circle().fill(.white.opacity(0.14)))
    }
}

/// The map's one sheet at its middle height, its header the app's (MapSheetHeader).
private struct MapSheetShot<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> AnyView
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 40, height: 5).frame(maxWidth: .infinity)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 28))
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                trailing()
            }
            content()
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.top, 10)
        .frame(height: 400)
        .background(UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34).fill(Color(red: 0.16, green: 0.18, blue: 0.20).opacity(0.97)))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

private func sheetRow<L: View, R: View>(@ViewBuilder _ leading: () -> L, @ViewBuilder trailing: () -> R) -> some View {
    HStack(spacing: 12) { leading(); Spacer(minLength: 6); trailing() }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.08)))
}

/// Prayers on: each marked prayer a pin where it was prayed, in its grade's colour (a masjid one with the masjid glyph),
/// a cluster of three, you; the sheet lists the prayers in view.
private struct PrayerPinsScene: View {
    var sheet = true
    var body: some View {
        ZStack(alignment: .topLeading) {
            MapGround()
            // Pins in the band the panel shows, just above the sheet (it starts at y 452; the page lifts the phone).
            balloon(.green, "hands.and.sparkles.fill", 80, 360)
            balloon(.yellow, "hands.and.sparkles.fill", 300, 410)
            balloon(.green, "building.columns.fill", 200, 345)
            balloon(.red, "hands.and.sparkles.fill", 130, 420)
            MapBalloon(color: .green, count: 3).position(x: 330, y: 335)
            Circle().fill(Color.blue).frame(width: 20, height: 20).overlay(Circle().stroke(.white, lineWidth: 4)).position(x: 235, y: 405)
            MapChrome(status: "8 prayers in view", explore: "hands.and.sparkles.fill")
            if sheet {
                MapSheetShot(title: "Prayer spots", subtitle: "8 in view", trailing: {
                    AnyView(Label("All time", systemImage: "line.3.horizontal.decrease")
                        .font(.system(size: 15, weight: .medium)).padding(.horizontal, 14).frame(height: 38)
                        .background(Capsule().fill(.white.opacity(0.1))))
                }) {
                    Text("TODAY").font(.system(size: 13, weight: .medium)).kerning(1).foregroundStyle(.white.opacity(0.45))
                    row("sun.max", "Dhuhr", "1:24 PM", "1:10 PM – 4:50 PM · 14 min in", 100, "Perfect", .green)
                    row("sunrise", "Fajr", "5:52 AM", "5:30 AM – 6:50 AM · 22 min in", 88, "Middle", .green)
                }
            }
        }
    }
    private func balloon(_ c: Color, _ s: String, _ x: CGFloat, _ y: CGFloat) -> some View {
        MapBalloon(color: c, symbol: s).position(x: x, y: y)
    }
    private func row(_ symbol: String, _ name: String, _ at: String, _ line: String, _ score: Int, _ grade: String, _ c: Color) -> some View {
        sheetRow {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.white.opacity(0.7)).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                (Text(name).font(.system(size: 17, weight: .semibold)) + Text(" prayed \(at)").font(.system(size: 17)).foregroundColor(.white.opacity(0.6)))
                Text(line).font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }
        } trailing: {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) { Circle().fill(c).frame(width: 7, height: 7); Text("\(score)").font(.system(size: 19, weight: .semibold)) }
                Text(grade).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// Mosques on: the green masjid pins, the nearest card first (drive time, distance, Show), more under it.
private struct MosqueFinderScene: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            MapGround()
            for_(CGPoint(x: 85, y: 350)); for_(CGPoint(x: 290, y: 415)); for_(CGPoint(x: 170, y: 420))
            MapBalloon(color: .green, count: 4).position(x: 320, y: 335)
            Circle().fill(Color.blue).frame(width: 20, height: 20).overlay(Circle().stroke(.white, lineWidth: 4)).position(x: 215, y: 375)
            MapChrome(status: "12 mosques nearby", explore: "building.columns.fill")
            MapSheetShot(title: "Mosques", subtitle: "12 near you", trailing: {
                AnyView(HStack(spacing: 0) {
                    Image(systemName: "car.fill").frame(width: 40, height: 34).background(Capsule().fill(.white.opacity(0.18)))
                    Image(systemName: "figure.walk").frame(width: 40, height: 34)
                }
                .font(.system(size: 15)).padding(3).background(Capsule().fill(.white.opacity(0.08))))
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("NEAREST", systemImage: "location.fill").font(.system(size: 12, weight: .semibold)).kerning(1)
                        .foregroundStyle(Color.sage)
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns.fill").font(.system(size: 22)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(Circle().fill(Color.sage))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ExplorePreset.masjid).font(.system(size: 20, weight: .semibold))
                            Text("1200 Oak St, \(ExplorePreset.city)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    HStack(spacing: 14) {
                        Label("4 min", systemImage: "car.fill"); Label("1.2 mi", systemImage: "arrow.triangle.turn.up.right.diamond")
                        Spacer()
                        Text("Show ›").foregroundStyle(Color.sage)
                    }
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.08)))
                Text("MORE NEARBY").font(.system(size: 12, weight: .medium)).kerning(1).foregroundStyle(.white.opacity(0.45))
                more("Islamic Center of \(ExplorePreset.city)", "2.4 mi", "7 min")
                more("Masjid Omar", "3.1 mi", "9 min")
            }
        }
    }
    private func for_(_ p: CGPoint) -> some View { MapBalloon(color: .green, symbol: "building.columns.fill").position(p) }
    private func more(_ name: String, _ far: String, _ drive: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns.fill").font(.system(size: 14)).foregroundStyle(Color.sage)
                .frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.08)))
            Text(name).font(.system(size: 16, weight: .medium)).lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(far).font(.system(size: 15))
                Label(drive, systemImage: "car.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

/// A Friday on the Salah page: Asr on in the circle, and the list with Dhuhr counted as Jumu'ah at the masjid.
private struct JumuahScene: View {
    private let bg = Color(red: 0.11, green: 0.12, blue: 0.13)
    var body: some View {
        ZStack(alignment: .top) {
            bg
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "line.3.horizontal")
                    Spacer()
                    Label(ExplorePreset.city, systemImage: "location.fill").font(.system(size: 14))
                    Spacer()
                    Image(systemName: "paintpalette")
                }
                .font(.system(size: 18)).foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 24).padding(.top, 64)
                ring.padding(.top, 34)
                Text("FRIDAY").font(.system(size: 13, weight: .medium)).kerning(1.5).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 44).padding(.top, 30)
                VStack(spacing: 0) {
                    row("Fajr", "5:52 AM", done: .green)
                    row("Jumu'ah", "1:24 PM", done: .green, masjid: true)
                    row("Asr", "now", done: nil, now: true)
                    row("Maghrib", "7:40 PM", done: nil)
                    row("Isha", "9:05 PM", done: nil)
                }
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.white.opacity(0.05)))
                .padding(.horizontal, 30).padding(.top, 10)
            }
        }
        .foregroundStyle(.white)
    }
    private var ring: some View {
        let p = ShownPrayer.now
        return ZStack {
            Circle().stroke(.white.opacity(0.07), lineWidth: 14)
            Circle().trim(from: 0, to: p.progress).stroke(Color.yellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(4)
            VStack(spacing: 4) {
                Label(p.name, systemImage: "sun.haze").font(.system(size: 30, weight: .light))
                Text("\(p.left) left").font(.system(size: 15)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: 180, height: 180)
    }
    private func row(_ name: String, _ time: String, done: Color?, masjid: Bool = false, now: Bool = false) -> some View {
        HStack(spacing: 14) {
            Group {
                if let done { Circle().fill(done.opacity(0.85)) }
                else { Circle().strokeBorder(.white.opacity(now ? 0.6 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: now ? [] : [3, 3])) }
            }
            .frame(width: 15, height: 15)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 19, weight: masjid ? .medium : .regular))
                    if masjid { Image(systemName: "building.columns.fill").font(.system(size: 13)).foregroundStyle(Color.sage) }
                }
                if masjid {
                    Text("at \(ExplorePreset.masjid)").font(.system(size: 13, weight: .light, design: .rounded)).foregroundStyle(Color.sage)
                }
            }
            Spacer()
            Text(masjid ? "100" : time).font(.system(size: 16, weight: masjid ? .semibold : .regular))
                .foregroundStyle(masjid ? Color.green : .white.opacity(done == nil && !now ? 0.45 : 0.75))
        }
        .opacity(done == nil && !now ? 0.75 : 1)
        .padding(.horizontal, 22).padding(.vertical, 12)
    }
}
