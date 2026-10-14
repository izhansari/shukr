//
//  RingDepthMocks.swift
//  shukr
//
//  Settings → My Dev Stuff → Ring depth (owner, 2026-10-14: "make the ring more apparent … for both light and dark",
//  after Bradley's app icon, decision app-icon-depth D). Mock-ups only — no real ring changes: each place the soft ring
//  shows, today's recipe beside the icon's lifted one, scaled to that ring's band, light or dark. DEBUG `-demoRingDepth`.
//
//  Today (WidgetSoftBand / WatchSoftBand / LASoftBand; NeuRingTrack is the same idea at fixed 2 pt): the band in the
//  surface colour, one shade down-right (radius 0.6 band, offset 0.3), one light up-left (0.9, −0.3).
//  Lifted (IconMocks depth 3, at its 18 pt band): a long soft drop (black 16 % light / 45 % dark, blur 0.67 band,
//  offset 0.44, 0.61); two shades stacked down-right (0.44 / 0.33, 0.28 / 0.2) and two lights up-left; a lit top-left
//  rim (white 100 % / 22 %, a sixth of the band) and a shaded bottom-right one (black 12 % / 35 %).
//

import SwiftUI

struct RingDepthMockPage: View {
    @State private var dark = false
    @Environment(\.colorScheme) private var system
    private var scheme: ColorScheme { dark ? .dark : .light }

    var body: some View {
        List {
            Section {
                Picker("Look", selection: $dark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Mock-ups only: nothing in the app changes. Left is today's ring, right the app icon's lifted one.")
            }
            place("The Salah circle", "The main ring on the Salah page and setup's welcome card") { lifted in
                SalahCircleMock(lifted: lifted).scaleEffect(0.62).frame(width: 150, height: 150)
            }
            place("Live Activity card", "Also Siri's Time Left and I Prayed cards", stacked: true) { lifted in
                LACardMock(lifted: lifted)
            }
            place("Prayers widget", "Home Screen and StandBy") { lifted in
                WidgetMock(lifted: lifted).scaleEffect(0.82).frame(width: 140, height: 140)
            }
            place("Apple Watch", "The watch's Salah ring") { lifted in
                WatchMock(lifted: lifted).scaleEffect(0.7).frame(width: 140, height: 150)
            }
        }
        .navigationTitle("Ring depth")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { dark = system == .dark }
    }

    @ViewBuilder private func place<V: View>(_ title: String, _ note: String, stacked: Bool = false,
                                             @ViewBuilder _ mock: @escaping (Bool) -> V) -> some View {
        Section {
            Group {
                if stacked {
                    VStack(spacing: 14) {
                        labelled("Today") { mock(false) }
                        labelled("Lifted") { mock(true) }
                    }
                } else {
                    HStack(spacing: 0) {
                        labelled("Today") { mock(false) }.frame(maxWidth: .infinity)
                        labelled("Lifted") { mock(true) }.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.vertical, 12)
            .environment(\.colorScheme, scheme)
            .listRowBackground(RingDepthColors.page(scheme))
        } header: {
            Text(title)
        } footer: {
            Text(note)
        }
    }

    private func labelled<V: View>(_ word: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(spacing: 8) {
            v()
            Text(word).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

/// The soft surfaces (WidgetSoft / WatchNeu / LASoft share them; the app's grey-blue theme is the same light grey).
enum RingDepthColors {
    static func page(_ s: ColorScheme) -> Color { s == .dark ? Color(white: 0.10) : Color(red: 0.890, green: 0.898, blue: 0.933) }
    static func shade(_ s: ColorScheme) -> Color { s == .dark ? .black.opacity(0.75) : .black.opacity(0.25) }
    static func light(_ s: ColorScheme) -> Color { s == .dark ? .white.opacity(0.06) : .white }
    static let arc = Color(red: 0.96, green: 0.77, blue: 0.20)   // on time: yellow
}

/// One soft ring: the raised band, today's way or lifted, then the prayer's arc on it.
struct SoftRingMock: View {
    let diameter: CGFloat
    let band: CGFloat
    var arcWidth: CGFloat? = nil
    var progress: CGFloat = 0.42
    let lifted: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let w = band
        let surface = RingDepthColors.page(scheme), shade = RingDepthColors.shade(scheme), light = RingDepthColors.light(scheme)
        ZStack {
            if lifted {
                Circle().stroke(lineWidth: w)
                    .foregroundStyle(Color.black.opacity(scheme == .dark ? 0.45 : 0.16))
                    .blur(radius: w * 0.67).offset(x: w * 0.44, y: w * 0.61)
                    .frame(width: diameter, height: diameter)
                Circle().stroke(surface, lineWidth: w)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: shade, radius: w * 0.44, x: w / 3, y: w / 3)
                    .shadow(color: shade, radius: w * 0.28, x: w * 0.2, y: w * 0.2)
                    .shadow(color: light, radius: w * 0.44, x: -w / 3, y: -w / 3)
                    .shadow(color: light, radius: w * 0.22, x: -w / 6, y: -w / 6)
                Circle().stroke(LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.22 : 1), .white.opacity(0)],
                                               startPoint: .topLeading, endPoint: .center), lineWidth: max(w / 6, 0.75))
                    .frame(width: diameter + w, height: diameter + w)
                Circle().stroke(LinearGradient(colors: [.black.opacity(0), .black.opacity(scheme == .dark ? 0.35 : 0.12)],
                                               startPoint: .center, endPoint: .bottomTrailing), lineWidth: max(w * 0.14, 0.75))
                    .frame(width: diameter + w, height: diameter + w)
            } else {
                Circle().stroke(surface, lineWidth: w)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: shade, radius: w * 0.6, x: w * 0.3, y: w * 0.3)
                    .shadow(color: light, radius: w * 0.9, x: -w * 0.3, y: -w * 0.3)
            }
            Circle().trim(from: 0, to: progress)
                .stroke(RingDepthColors.arc, style: StrokeStyle(lineWidth: arcWidth ?? w * 0.35, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter + w * 2, height: diameter + w * 2)
    }
}

private struct SalahCircleMock: View {
    let lifted: Bool
    var body: some View {
        ZStack {
            SoftRingMock(diameter: 200, band: 18, arcWidth: 5, lifted: lifted)
            VStack(spacing: 2) {
                Image(systemName: "sun.haze").font(.system(size: 22, weight: .light))
                Text("Asr").font(.system(size: 34, weight: .light, design: .rounded))
                Text("1 hr 50 min left").font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LACardMock: View {
    let lifted: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                SoftRingMock(diameter: 52, band: 9, arcWidth: 3.5, lifted: lifted)
                Image(systemName: "sun.haze").font(.system(size: 16, weight: .light))
            }
            .frame(width: 73, height: 73)
            VStack(alignment: .leading, spacing: 1.5) {
                Text("Asr").font(.system(size: 20))
                Text("1 hr, 50 min left").font(.system(size: 14))
                Text("ends 7:40 PM").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(RingDepthColors.page(scheme))
                    .shadow(color: RingDepthColors.shade(scheme), radius: 4, x: 2, y: 2)
                    .shadow(color: RingDepthColors.light(scheme), radius: 4, x: -2, y: -2))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(RingDepthColors.page(scheme)))
    }
}

private struct WidgetMock: View {
    let lifted: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            SoftRingMock(diameter: 104, band: 12, arcWidth: 4, lifted: lifted)
            VStack(spacing: 1) {
                Image(systemName: "sun.haze").font(.system(size: 12, weight: .light))
                Text("Asr").font(.system(size: 17, weight: .regular, design: .rounded))
                Text("ends 7:40 PM").font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, height: 170)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(RingDepthColors.page(scheme)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

private struct WatchMock: View {
    let lifted: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            RingDepthColors.page(scheme)
            SoftRingMock(diameter: 132, band: 10, arcWidth: 6, lifted: lifted)
            VStack(spacing: 2) {
                Image(systemName: "sun.haze").font(.system(size: 14, weight: .light))
                Text("Asr").font(.system(size: 22, weight: .regular, design: .rounded))
                Text("ends 7:40 PM").font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 198, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 54, style: .continuous).fill(Color(white: 0.13)))
    }
}
