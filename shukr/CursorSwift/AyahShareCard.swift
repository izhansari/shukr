//
//  AyahShareCard.swift
//  shukr
//
//  The image the Daily Ayah share button sends (2026-09-25). 9:16 (Stories-ready), rendered
//  with ImageRenderer at 3× (1080 × 1920 px). Three looks, picked in `AyahShareOptionsSheet`:
//  - mint:    soft mint → sage gradient, deep-green ink ("light but a bit more green")
//  - grain:   the welcome screen itself — its wavy green / black gradient (AnimatedWavyGradient,
//             held at its first frame) and grain (NoiseOverlay) on the light welcome screen's
//             white base, with a glassy capsule mark
//  - forest:  deep green → near-black with a soft light from the top (the first version)
//  Same layout for all: date line, ayah, dot, translation, reference, translator, and the main
//  circle as a tiny mark next to a thin "shukr", clear of the areas Stories cover.
//

import SwiftUI

enum AyahShareStyle: String, CaseIterable, Identifiable {
    case mint, grain, forest
    var id: String { rawValue }
    var title: String { rawValue }
}

struct AyahShareCard: View {
    let arabic: String
    let english: String
    let translator: String
    let reference: String   // e.g. "Al-Baqarah · 2:255"
    var date: Date = Date()
    var style: AyahShareStyle = .mint
    /// The grain look's base: the light welcome screen (owner's pick, 2026-09-25); dark kept
    /// for later.
    var darkBase: Bool = false

    /// 9:16 — Instagram / WhatsApp Stories. 3× → 1080 × 1920 px.
    static let size = CGSize(width: 360, height: 640)

    private var ink: Color {
        style == .mint ? Color(red: 0.06, green: 0.15, blue: 0.10) : .white
    }
    private var accent: Color {
        switch style {
        case .mint: Color(red: 0.12, green: 0.52, blue: 0.29)
        case .grain: Color(red: 0.55, green: 0.90, blue: 0.62)
        case .forest: Color.green.opacity(0.9)
        }
    }

    var body: some View {
        ZStack {
            background
            if style != .grain { ShareCardGrain(dark: style != .mint) }

            VStack(spacing: 0) {
                // Stories put their own UI over the top ~14 % and bottom ~18 %: keep clear of both.
                Text("daily ayah · \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))".lowercased())
                    .font(.system(size: 9, weight: .light, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(ink.opacity(style == .grain ? 0.7 : 0.45))
                    .padding(.top, 104)

                Spacer(minLength: 16)

                Text(arabic)
                    .font(.custom("KFGQPCUthmanTahaNaskh", size: 29))
                    .foregroundStyle(ink.opacity(style == .grain ? 1 : 0.92))
                    .shadow(color: style == .grain ? .black.opacity(0.35) : .clear, radius: 6)
                    .multilineTextAlignment(.center)
                    .lineSpacing(9)
                    .minimumScaleFactor(0.35)
                    .padding(.horizontal, 32)

                Circle()
                    .fill(accent.opacity(0.8))
                    .frame(width: 4, height: 4)
                    .padding(.vertical, 22)

                Text(english)
                    .font(.system(size: 13.5, weight: .light, design: .rounded))
                    .foregroundStyle(ink.opacity(style == .mint ? 0.68 : style == .grain ? 0.9 : 0.72))
                    .shadow(color: style == .grain ? .black.opacity(0.35) : .clear, radius: 4)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .minimumScaleFactor(0.45)
                    .padding(.horizontal, 38)

                Text(reference)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.top, 16)
                Text(translator)
                    .font(.system(size: 7, weight: .light, design: .rounded))
                    .foregroundStyle(ink.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .padding(.top, 3)
                    .padding(.horizontal, 40)

                Spacer(minLength: 16)

                mark
                Text("download on the App Store")
                    .font(.system(size: 8, weight: .light, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(ink.opacity(style == .grain ? 0.7 : 0.4))
                    .padding(.top, 5)
                    .padding(.bottom, 128)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .mint:
            LinearGradient(colors: [Color(red: 0.93, green: 0.97, blue: 0.93),
                                    Color(red: 0.80, green: 0.90, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.55), .clear],
                           center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: 260)
        case .grain:
            // The welcome screen's own layers (shukrApp.swift), on its base.
            darkBase ? Color.black : Color.white
            AnimatedWavyGradient()
            NoiseOverlay()
                .blendMode(.overlay)
                .opacity(0.3)
            // The light base leaves pale edges and a pale band at the bottom, where the white
            // text washed out: a soft dark veil down the text column keeps it readable.
            LinearGradient(colors: [Color.black.opacity(0.28), Color.black.opacity(0.18), Color.black.opacity(0.34)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.black.opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.45), startRadius: 40, endRadius: 330)
        case .forest:
            LinearGradient(colors: [Color(red: 0.06, green: 0.16, blue: 0.11), Color(red: 0.02, green: 0.04, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.green.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 420)
        }
    }

    /// The main circle, tiny, next to a thin "shukr" — in a glassy capsule on the welcome look,
    /// like the welcome screen's button.
    @ViewBuilder private var mark: some View {
        let row = HStack(spacing: 8) {
            ZStack {
                Circle().stroke(ink.opacity(0.14), lineWidth: 2.4)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(0.5), radius: 2)
            }
            .frame(width: 15, height: 15)
            Text("shukr")
                .font(.system(size: 18, weight: .thin, design: .rounded))
                .foregroundStyle(ink.opacity(0.8))
        }
        if style == .grain {
            row
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(radius: 5)
        } else {
            row
        }
    }

    /// The card as an image, 1080 × 1920.
    @MainActor
    func render() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Fine grain, fixed (seeded) so the card looks the same every time it's rendered.
private struct ShareCardGrain: View {
    let dark: Bool
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5EED
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            for _ in 0..<3600 {
                let x = next() * size.width, y = next() * size.height
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)),
                             with: .color((dark ? Color.white : Color.black).opacity(0.05 + 0.07 * next())))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Picker sheet

/// Share → pick a look, then share the image. The three cards render once when the sheet opens.
struct AyahShareOptionsSheet: View {
    let arabic: String
    let english: String
    let translator: String
    let reference: String

    @AppStorage("ayahShareStyle") private var styleRaw = AyahShareStyle.mint.rawValue
    @State private var images: [AyahShareStyle: UIImage] = [:]

    private var style: AyahShareStyle { AyahShareStyle(rawValue: styleRaw) ?? .mint }

    var body: some View {
        VStack(spacing: 18) {
            Text("share today's ayah")
                .font(.subheadline)
                .fontWeight(.light)
                .foregroundStyle(.secondary)
                .padding(.top, 22)

            HStack(spacing: 14) {
                ForEach(AyahShareStyle.allCases) { option in
                    let selected = option == style
                    VStack(spacing: 6) {
                        Group {
                            if let image = images[option] {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill))
                            }
                        }
                        .frame(width: 92, height: 92 * 16 / 9)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selected ? Color.green : Color(.separator), lineWidth: selected ? 2 : 0.5)
                        )
                        .scaleEffect(selected ? 1.04 : 1)
                        Text(option.title)
                            .font(.caption)
                            .fontWeight(selected ? .medium : .light)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                    .onTapGesture {
                        triggerSomeVibration(type: .light)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { styleRaw = option.rawValue }
                    }
                }
            }

            if let image = images[style] {
                // Only the image is sent; iOS wants a title for the share sheet's preview row.
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("today's daily ayah from shukr", image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
            } else {
                ProgressView().frame(height: 50)
            }
            Spacer(minLength: 0)
        }
        .fontDesign(.rounded)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .task {
            for option in AyahShareStyle.allCases where images[option] == nil {
                images[option] = AyahShareCard(arabic: arabic, english: english, translator: translator,
                                               reference: reference, style: option).render()
            }
        }
    }
}
