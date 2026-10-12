//
//  MadhabSketchMocks.swift
//  shukr
//
//  DEBUG only: versions of the setup's Shafi'i / Hanafi card graphic to compare (owner, 2026-10-12: the shrunk card's
//  sketch "looks a little funny"). `-laTuner YES -madhabMocks YES` shows them as the cards would, side by side.
//

#if DEBUG
import SwiftUI

struct MadhabSketchMocks: View {
    private let versions: [(String, String)] = [
        ("A", "Now"),
        ("B", "Sun's ray over the post to the shadow's tip"),
        ("C", "A person and their shadow"),
        ("D", "Measured: 1× / 2× under the shadow"),
        ("E", "The sun's arc, lower for Hanafi"),
        ("F", "Just the lengths: the object, then its shadow"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(versions, id: \.0) { v in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(v.0) · \(v.1)").font(.system(.subheadline, design: .rounded, weight: .semibold))
                        HStack(spacing: 14) {
                            card(v.0, title: "Shafi'i", time: "Asr 4:14 PM", lengths: 1, selected: true)
                            card(v.0, title: "Hanafi", time: "Asr 5:02 PM", lengths: 2, selected: false)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private func card(_ v: String, title: String, time: String, lengths: CGFloat, selected: Bool) -> some View {
        VStack(spacing: 8) {
            sketch(v, lengths: lengths, selected: selected)
                .frame(height: 48)
            Text(title).font(.system(.title3, design: .rounded))
            Text(time)
                .font(.system(.title3, design: .rounded, weight: .light))
                .foregroundStyle(selected ? Color.sage : .primary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(selected ? Color.sage.opacity(0.10) : Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Color.sage.opacity(0.6) : .clear, lineWidth: 1))
    }

    @ViewBuilder private func sketch(_ v: String, lengths: CGFloat, selected: Bool) -> some View {
        switch v {
        case "A": SketchNow(lengths: lengths)
        case "B": SketchRay(lengths: lengths)
        case "C": SketchPerson(lengths: lengths)
        case "D": SketchMeasured(lengths: lengths)
        case "E": SketchArc(lengths: lengths)
        default: SketchBars(lengths: lengths)
        }
    }
}

private let mSun = Color.orange.opacity(0.8)
private let mShadow = Color.sage.opacity(0.85)

/// A: today's (the post at the left, the sun beside it).
private struct SketchNow: View {
    let lengths: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let unit = min(size.height * 0.6, (size.width - 40) / 2.2)
            let groundY = size.height - 4, postX: CGFloat = 32
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 6, y: groundY)); p.addLine(to: CGPoint(x: size.width - 6, y: groundY)) },
                       with: .color(.secondary.opacity(0.3)), lineWidth: 1)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX + unit * lengths, y: groundY)) },
                       with: .color(mShadow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX, y: groundY - unit)) },
                       with: .color(.primary.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let sunY = groundY - unit * (lengths == 1 ? 1.1 : 0.62)
            ctx.fill(Path(ellipseIn: CGRect(x: 8, y: sunY - 6, width: 12, height: 12)), with: .color(mSun))
        }
    }
}

/// B: the post, its shadow, and the sun's ray grazing the post's top to the shadow's tip — why it's that long.
private struct SketchRay: View {
    let lengths: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let groundY = size.height - 3
            let post = size.height * 0.62
            let unit = post                       // the shadow measured in post-lengths
            let total = unit * 2                  // room for the longest (Hanafi) shadow
            let left = (size.width - total) / 2 + 6
            let postX = left
            let tip = CGPoint(x: postX + unit * lengths, y: groundY)
            let top = CGPoint(x: postX, y: groundY - post)
            // The ray, from beyond the post's top (the sun's side) down to the tip.
            let dx = tip.x - top.x, dy = tip.y - top.y
            let back = CGPoint(x: top.x - dx * 0.35, y: top.y - dy * 0.35)
            ctx.stroke(Path { p in p.move(to: back); p.addLine(to: tip) },
                       with: .color(mSun.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: back.x - 6, y: back.y - 6, width: 12, height: 12)), with: .color(mSun))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 4, y: groundY)); p.addLine(to: CGPoint(x: size.width - 4, y: groundY)) },
                       with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: tip) },
                       with: .color(mShadow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: top) },
                       with: .color(.primary.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }
}

/// C: a standing figure and its shadow on the ground, one or two of its heights long.
private struct SketchPerson: View {
    let lengths: CGFloat
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let figure = h * 0.82
            let total = figure * 2
            let x0 = (g.size.width - total) / 2
            ZStack(alignment: .bottomLeading) {
                Capsule().fill(mShadow.opacity(0.55))
                    .frame(width: figure * lengths, height: 5)
                    .offset(x: x0 + figure * 0.18, y: 0)
                Image(systemName: "figure.stand")
                    .resizable().scaledToFit()
                    .frame(height: figure)
                    .foregroundStyle(.primary.opacity(0.75))
                    .offset(x: x0 - figure * 0.12, y: -2)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(mSun)
                    .offset(x: x0 - figure * 0.55, y: -(lengths == 1 ? h * 0.72 : h * 0.42))
            }
            .frame(width: g.size.width, height: h, alignment: .bottomLeading)
        }
    }
}

/// D: the post and its shadow with the post's length marked on each: 1× / 2×.
private struct SketchMeasured: View {
    let lengths: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let groundY = size.height - 14
            let post = groundY - 4
            let total = post * 2
            let postX = (size.width - total) / 2
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX + post * lengths, y: groundY)) },
                       with: .color(mShadow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: CGPoint(x: postX, y: groundY - post)) },
                       with: .color(.primary.opacity(0.75)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            // A tick at each post-length along the shadow.
            for i in 1...Int(lengths) {
                let x = postX + post * CGFloat(i)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: groundY - 5)); p.addLine(to: CGPoint(x: x, y: groundY + 5)) },
                           with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            }
            let label = ctx.resolve(Text(lengths == 1 ? "1×" : "2×").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.secondary))
            ctx.draw(label, at: CGPoint(x: postX + post * lengths / 2, y: groundY + 10))
        }
    }
}

/// E: the sun on its afternoon arc — high for Shafi'i, lower for Hanafi — over a small post and shadow.
private struct SketchArc: View {
    let lengths: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let groundY = size.height - 3
            let r = min(size.width / 2 - 8, size.height - 6)
            let c = CGPoint(x: size.width / 2, y: groundY)
            ctx.stroke(Path { p in p.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false) },
                       with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 4, y: groundY)); p.addLine(to: CGPoint(x: size.width - 4, y: groundY)) },
                       with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            // Afternoon: west (left of centre in this drawing is east) — the sun on the right, lower when later.
            let angle = Angle.degrees(lengths == 1 ? -45 : -27)
            let sunP = CGPoint(x: c.x + r * cos(angle.radians), y: c.y + r * sin(angle.radians))
            ctx.fill(Path(ellipseIn: CGRect(x: sunP.x - 6, y: sunP.y - 6, width: 12, height: 12)), with: .color(mSun))
            let post: CGFloat = r * 0.32
            ctx.stroke(Path { p in p.move(to: CGPoint(x: c.x, y: groundY)); p.addLine(to: CGPoint(x: c.x - post * lengths, y: groundY)) },
                       with: .color(mShadow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: c.x, y: groundY)); p.addLine(to: CGPoint(x: c.x, y: groundY - post)) },
                       with: .color(.primary.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// F: no scene — the object's length, then its shadow as one or two of those lengths.
private struct SketchBars: View {
    let lengths: CGFloat
    var body: some View {
        GeometryReader { g in
            let unit = (g.size.width - 24) / 2
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Capsule().fill(.primary.opacity(0.7)).frame(width: unit, height: 5)
                    Text("object").font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    ForEach(0..<Int(lengths), id: \.self) { _ in
                        Capsule().fill(mShadow).frame(width: unit - 1.5, height: 5)
                    }
                }
                Text("shadow").font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .leading)
            .padding(.leading, 12)
        }
    }
}
#endif

#if DEBUG
/// Full cards with option B, calmer colours (owner: "really naive and a little Android"): three layouts, each with its
/// height, for the little room left once the method folds. `-laTuner YES -madhabCards YES`.
struct MadhabCardMocks: View {
    @State private var pick = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                layout("1 · Today's card, option B, calmer colours") { l1 }
                layout("2 · Shorter: the check in the corner, a one-line rule") { l2 }
                layout("3 · Rows: the drawing beside the words") { l3 }
            }
            .padding(.vertical, 16)
        }
    }

    private func layout<V: View>(_ title: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold)).padding(.horizontal, 24)
            v().padding(.horizontal, 24)
                .overlay(alignment: .bottomTrailing) { HeightTag() }
        }
    }

    // 1: the card as it is, graphic B, no mint fill — the pick is a sage outline + check.
    private var l1: some View {
        HStack(spacing: 14) {
            ForEach(0..<2) { i in
                Button { pick = i } label: {
                    VStack(spacing: 6) {
                        CalmRay(lengths: CGFloat(i + 1), picked: pick == i).frame(height: 50)
                        Text(i == 0 ? "Shafi'i" : "Hanafi").font(.system(.title3, design: .rounded))
                        Text(i == 0 ? "Maliki, Hanbali too" : " ").font(.caption).foregroundStyle(.tertiary)
                        Text(i == 0 ? "Asr 4:14 PM" : "Asr 5:02 PM")
                            .font(.system(.title2, design: .rounded, weight: .light)).monospacedDigit()
                        Text(i == 0 ? "when a shadow is as long as the object" : "when a shadow is twice the object's length")
                            .font(.system(.footnote, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        mark(pick == i)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .background(card(pick == i))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 2: shorter — the check in the top corner, "1 shadow-length" / "2 shadow-lengths" under the time.
    private var l2: some View {
        HStack(spacing: 14) {
            ForEach(0..<2) { i in
                Button { pick = i } label: {
                    VStack(spacing: 4) {
                        CalmRay(lengths: CGFloat(i + 1), picked: pick == i).frame(height: 46).padding(.top, 4)
                        Text(i == 0 ? "Shafi'i" : "Hanafi").font(.system(.title3, design: .rounded))
                        Text(i == 0 ? "Asr 4:14 PM" : "Asr 5:02 PM")
                            .font(.system(.title3, design: .rounded, weight: .light)).monospacedDigit()
                        Text(i == 0 ? "shadow = its length" : "shadow = twice its length")
                            .font(.system(.caption, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .background(card(pick == i))
                    .overlay(alignment: .topTrailing) { mark(pick == i).padding(8) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 3: two rows, the drawing on the left.
    private var l3: some View {
        VStack(spacing: 10) {
            ForEach(0..<2) { i in
                Button { pick = i } label: {
                    HStack(spacing: 12) {
                        CalmRay(lengths: CGFloat(i + 1), picked: pick == i).frame(width: 96, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(i == 0 ? "Shafi'i" : "Hanafi").font(.system(.body, design: .rounded, weight: .medium))
                                Spacer()
                                Text(i == 0 ? "Asr 4:14 PM" : "Asr 5:02 PM")
                                    .font(.system(.body, design: .rounded, weight: .light)).monospacedDigit()
                            }
                            Text(i == 0 ? "shadow as long as the object · Maliki, Hanbali too" : "shadow twice the object's length")
                                .font(.system(.caption, design: .rounded, weight: .light)).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        mark(pick == i)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(card(pick == i))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card(_ picked: Bool) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.secondarySystemBackground))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(picked ? Color.sage : .clear, lineWidth: 1.5))
    }

    private func mark(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .light))
            .foregroundStyle(on ? Color.sage : Color.secondary.opacity(0.4))
    }
}

/// Option B in quiet tones: grey sun and ray, ink post, the shadow grey — sage only on the picked card.
struct CalmRay: View {
    let lengths: CGFloat
    let picked: Bool
    var body: some View {
        Canvas { ctx, size in
            let groundY = size.height - 3
            let post = size.height * 0.6
            let total = post * 2
            let postX = (size.width - total) / 2 + 8
            let tip = CGPoint(x: postX + post * lengths, y: groundY)
            let top = CGPoint(x: postX, y: groundY - post)
            let dx = tip.x - top.x, dy = tip.y - top.y
            let back = CGPoint(x: top.x - dx * 0.38, y: top.y - dy * 0.38)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: 4, y: groundY)); p.addLine(to: CGPoint(x: size.width - 4, y: groundY)) },
                       with: .color(.primary.opacity(0.12)), lineWidth: 1)
            ctx.stroke(Path { p in p.move(to: back); p.addLine(to: tip) },
                       with: .color(.primary.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2.5, 3]))
            // The sun: a soft ring, not an orange dot.
            ctx.stroke(Path(ellipseIn: CGRect(x: back.x - 5.5, y: back.y - 5.5, width: 11, height: 11)),
                       with: .color(.primary.opacity(0.45)), lineWidth: 1.2)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: tip) },
                       with: .color(picked ? Color.sage : .primary.opacity(0.3)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            ctx.stroke(Path { p in p.move(to: CGPoint(x: postX, y: groundY)); p.addLine(to: top) },
                       with: .color(.primary.opacity(0.75)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// The block's height in points, small, for comparing what fits.
private struct HeightTag: View {
    @State private var h: CGFloat = 0
    var body: some View {
        Color.clear
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h = $0 }
            .overlay(alignment: .bottomTrailing) {
                Text("\(Int(h)) pt").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.red)
                    .offset(y: 14).padding(.trailing, 24)
            }
    }
}
#endif
