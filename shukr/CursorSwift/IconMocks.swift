//
//  IconMocks.swift
//  shukr
//
//  DEBUG only (ask app-icon-options): app icon mocks drawn with the app's own soft ring — `NeuRingTrack` on the public
//  look's grey-blue surface, its real shadows — rendered to PNGs. Launch with `-renderIconMocks`; the files land in the
//  app's Documents/icon-mocks/ (simulator: `simctl get_app_container <udid> com.betternorms.shukr data`).
//

#if DEBUG
import SwiftUI

@MainActor
enum IconMocks {
    /// One icon at 1024 pt: the surface, the real raised band scaled up, and what sits on it.
    struct Icon: View {
        /// G's variations: where the dot sits (degrees from the top, clockwise), its colour and size, a trail of arc
        /// behind it, and the band pressed in instead of raised.
        struct GStyle { var angle: Double = 45; var color: Color = .sage; var size: CGFloat = 26; var trail = false; var pressed = false }
        enum Mark { case none, arc, dot, boldDot, boldArc(CGFloat), g(GStyle) }
        var bold: Bool { switch mark { case .boldDot, .boldArc, .g: true; default: false } }
        var pressedBand: Bool { if case .g(let st) = mark { return st.pressed }; return false }
        let mark: Mark
        /// How far the band stands off the surface (owner 2026-10-14: "a bit more emphasized … so the ring pops up off
        /// the page"): 0 = G1 as shipped; 1 deeper shadows; 2 a thicker band, deeper still; 3 deeper with a lit top edge
        /// and a long soft drop.
        var depth = 0
        @Environment(\.circleTheme) private var theme
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            ZStack {
                theme.surface
                ZStack {
                    if pressedBand {
                        // Pressed into the surface: the band is a groove (NeuPressed's inner shadows on a ring).
                        Circle()
                            .strokeBorder(lineWidth: 18)
                            .frame(width: 208, height: 208)
                            .foregroundStyle(theme.surface
                                .shadow(.inner(color: theme.shade, radius: 5, x: 3, y: 3))
                                .shadow(.inner(color: theme.light, radius: 5, x: -3, y: -3)))
                    } else if bold && depth > 0 {
                        // Darker, not just wider (wider only washed out): the shade stacked, tighter, offset further.
                        let off: CGFloat = depth == 2 ? 8 : 6
                        ZStack {
                            if depth == 3 {
                                // A long soft drop: the whole ring lifted off the page.
                                Circle().stroke(lineWidth: 18).frame(width: 190, height: 190)
                                    .foregroundStyle(Color.black.opacity(scheme == .dark ? 0.45 : 0.16)).blur(radius: 12).offset(x: 8, y: 11)
                            }
                            Circle()
                                .stroke(lineWidth: depth == 2 ? 22 : 18)
                                .frame(width: 190, height: 190)
                                .foregroundStyle(theme.surface)
                                .shadow(color: theme.shade, radius: 8, x: off, y: off)
                                .shadow(color: theme.shade, radius: 5, x: off * 0.6, y: off * 0.6)
                                .shadow(color: depth == 2 ? Color.black.opacity(0.10) : .clear, radius: 2, x: 2, y: 2)   // a crisp edge
                                .shadow(color: theme.light, radius: 8, x: -off, y: -off)
                                .shadow(color: theme.light, radius: 4, x: -off * 0.5, y: -off * 0.5)
                            if depth == 3 {
                                // The band's top-left edge catching the light, its lower edge in shade.
                                Circle().stroke(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.22 : 1), .white.opacity(0)],
                                                               startPoint: .topLeading, endPoint: .center), lineWidth: 3)
                                    .frame(width: 208, height: 208)
                                Circle().stroke(LinearGradient(colors: [.black.opacity(0), .black.opacity(scheme == .dark ? 0.35 : 0.12)],
                                                               startPoint: .center, endPoint: .bottomTrailing), lineWidth: 2.5)
                                    .frame(width: 208, height: 208)
                            }
                        }
                    } else if bold {
                        // The same recipe as NeuRingTrack (the surface's band, a shade below-right, a light above-left),
                        // thickened and deepened for a 60 pt icon — at its real 6 pt the relief vanished.
                        Circle()
                            .stroke(lineWidth: 16)
                            .frame(width: 190, height: 190)
                            .foregroundStyle(theme.surface)
                            .shadow(color: theme.shade, radius: 7, x: 4, y: 4)
                            .shadow(color: theme.light, radius: 8, x: -4, y: -4)
                    } else {
                        NeuRingTrack()
                    }
                    switch mark {
                    case .none: EmptyView()
                    case .arc:
                        // The ring's arc as the circle draws it at its finest: the band's width, round ends, its glow.
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: AliveRingTuning.fine.band, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 200, height: 200)
                            .shadow(color: Color.green.opacity(AliveRingTuning.fine.glow), radius: 4)
                    case .g(let st):
                        let a = (st.angle - 90) * .pi / 180
                        if st.trail {
                            Circle()
                                .trim(from: max(0, st.angle / 360 - 0.18), to: st.angle / 360)
                                .stroke(LinearGradient(colors: [st.color.opacity(0), st.color.opacity(0.7)],
                                                       startPoint: .leading, endPoint: .trailing),
                                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 190, height: 190)
                        }
                        Circle().fill(st.color)
                            .frame(width: st.size, height: st.size)
                            .shadow(color: st.color.opacity(0.55), radius: 6)
                            .offset(x: 95 * cos(a), y: 95 * sin(a))
                    case .boldArc(let width):
                        // E on the thick band (owner: "E with a thicker soft band keeping the progress green as is").
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 190, height: 190)
                            .shadow(color: Color.green.opacity(AliveRingTuning.fine.glow), radius: 5)
                    case .boldDot:
                        Circle().fill(Color.sage)
                            .frame(width: 26, height: 26)
                            .shadow(color: Color.sage.opacity(0.55), radius: 6)
                            .offset(x: 95 * cos(-.pi / 4), y: 95 * sin(-.pi / 4))
                    case .dot:
                        // Option C's idea on the real ring: where you are in the window.
                        Circle().fill(Color.sage)
                            .frame(width: 15, height: 15)
                            .shadow(color: Color.sage.opacity(0.5), radius: 4)
                            .offset(x: 100 * cos(-.pi / 4), y: 100 * sin(-.pi / 4))
                    }
                }
                .scaleEffect(2.55)   // the 200 pt circle to ~510 of 1024, shadows and all
            }
            .frame(width: 1024, height: 1024)
        }
    }

    /// The tinted icon (iOS turns its brightness into the tint, so shadows on black vanish): T3 — a 0.5 → 0.22 band,
    /// a white dot. Its band follows the light icon's (owner 2026-10-14: today's tint, D's thickness — 18).
    struct TintedIcon: View {
        var band: CGFloat = 18
        var body: some View {
            ZStack {
                Color.black
                ZStack {
                    Circle().stroke(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.22)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: band)
                        .frame(width: 190, height: 190)
                    Circle().fill(.white).frame(width: 30, height: 30)
                        .offset(x: 95 * cos(-.pi / 4), y: 95 * sin(-.pi / 4))
                }
                .scaleEffect(2.55)
            }
            .frame(width: 1024, height: 1024)
        }
    }

    private static func write<V: View>(_ view: V, to file: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        try? data.write(to: file)
        print("ICONMOCK \(file.path)")
    }

    static func render() {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "icon-mocks")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marks: [(String, Icon.Mark)] = [("ring", .none), ("arc", .arc), ("dot", .dot), ("bold", .boldDot),
                                            ("boldarc", .boldArc(16)), ("boldarcthin", .boldArc(8)),
                                            ("g1", .g(.init())),
                                            ("g2", .g(.init(angle: 0))),
                                            ("g3", .g(.init(color: .green))),
                                            ("g4", .g(.init(size: 16))),
                                            ("g5", .g(.init(trail: true))),
                                            ("g6", .g(.init(pressed: true)))]
        // The depth variations of G1 (owner 2026-10-14: D = depth 3 shipped), light and dark.
        for depth in 0...3 {
            for scheme in [ColorScheme.light, .dark] {
                let view = Icon(mark: .g(.init()), depth: depth)
                    .environment(\.circleTheme, .publicLook)
                    .environment(\.colorScheme, scheme)
                write(view, to: folder.appending(path: "icon-depth\(depth)\(scheme == .dark ? "-dark" : "").png"))
            }
        }
        write(TintedIcon(), to: folder.appending(path: "icon-tinted.png"))
        guard !ProcessInfo.processInfo.arguments.contains("-iconDepthOnly") else { return }
        for (name, mark) in marks {
            for scheme in [ColorScheme.light, .dark] {
                let view = Icon(mark: mark)
                    .environment(\.circleTheme, .publicLook)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                guard let image = renderer.uiImage, let data = image.pngData() else { continue }
                let file = folder.appending(path: "icon-\(name)-\(scheme == .light ? "light" : "dark").png")
                try? data.write(to: file)
                print("ICONMOCK \(file.path)")
            }
        }
    }
}
#endif
