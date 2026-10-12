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
