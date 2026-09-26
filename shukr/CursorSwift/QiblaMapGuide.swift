//
//  QiblaMapGuide.swift  (MapGuide: the map's ? — qibla, prayer spots or mosques)
//  shukr
//
//  How the qibla map works, shown the first time the map opens and from its ? button (owner,
//  2026-09-25: people find the map's compass confusing — its arrows don't follow the phone the way
//  the Salah page's circle does — so explain why it's built this way and how to use it).
//  Three short pages, each with a small moving picture: the green line is computed (right even
//  when the compass isn't), the map turns qibla-up so the top of the phone is the qibla once the
//  streets match, and the ring is only the compass.
//

import SwiftUI

/// What the map's ? explains: the layer that's showing (owner, 2026-09-26).
enum MapGuideTopic: String, Identifiable {
    case qibla, prayers, mosques
    var id: String { rawValue }
    /// Shown once on its own the first time; the ? brings it back any time.
    var seenKey: String { self == .qibla ? "qiblaMapGuideSeen" : "mapGuideSeen.\(rawValue)" }
}

struct MapGuide: View {
    let topic: MapGuideTopic
    let onDone: () -> Void
    @State private var page = 0

    private struct Page {
        let title: String
        let body: String
    }

    private var pages: [Page] {
        switch topic {
        case .qibla: qiblaPages
        case .prayers: prayerPages
        case .mosques: mosquePages
        }
    }

    private let prayerPages = [
        Page(title: "Every prayer, where you prayed it",
             body: "Each pin is a prayer you marked, dropped where you were. The colour is its score — green early, yellow on time, red late, gray qaza."),
        Page(title: "Tap a pin to look back",
             body: "See the prayers at that spot: when you prayed, how far into the time you were, and the score. A number means a few pins close together — tap it too."),
        Page(title: "Filter what you see",
             body: "Use the bar at the bottom: pick a stretch of time, and tap a prayer to see only that one — every Fajr this month, say. ✕ takes you back to the qibla."),
    ]

    private let mosquePages = [
        Page(title: "Mosques around you",
             body: "Found on Apple Maps — mosques, masjids and Islamic centres, kept to places you can pray. Shops and restaurants are left out."),
        Page(title: "Tap one for the details",
             body: "How long it takes by car or on foot, a look at the entrance where Apple has it, and directions in Apple Maps or Google Maps."),
        Page(title: "Looking somewhere else?",
             body: "Move the map anywhere and tap \u{201C}Search this area\u{201D} to find the mosques there. Tap List to see them all, nearest first."),
    ]

    private let qiblaPages = [
        Page(title: "The green line is the qibla",
             body: "It's worked out from exactly where you're standing to the Kaaba — no compass involved. So it's right even when your phone's compass isn't."),
        Page(title: "The top of your phone is the qibla",
             body: "The map turns so the green line points straight up. Hold your phone in front of you and turn until the streets on the map match the ones around you — then you're facing the qibla."),
        Page(title: "The ring is your compass",
             body: "The blue arrow is where your phone thinks you're facing; the triangle is the qibla. Turn until they meet and the screen glows. Compasses drift near cars, metal and speakers — when they disagree, trust the line."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        illustration(i)
                            .frame(width: 150, height: 150)
                            .clipped()
                        VStack(spacing: 8) {
                            Text(pages[i].title)
                                .font(.system(size: 21, weight: .regular, design: .rounded))
                                .multilineTextAlignment(.center)
                            Text(pages[i].body)
                                .font(.system(size: 15, weight: .light, design: .rounded))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 28)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 28)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.primary.opacity(0.7) : Color.primary.opacity(0.18))
                        .frame(width: i == page ? 16 : 6, height: 6)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 16)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Got it")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().strokeBorder(Color.green, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder private func illustration(_ i: Int) -> some View {
        switch (topic, i) {
        case (.qibla, 0): GuideLinePicture()
        case (.qibla, 1): GuideRotatePicture()
        case (.qibla, _): GuideRingPicture()
        case (.prayers, 0): GuidePinsPicture()
        case (.prayers, 1): GuidePinCardPicture()
        case (.prayers, _): GuideFilterPicture()
        case (.mosques, 0): GuideMosquesPicture()
        case (.mosques, 1): GuideMosqueCardPicture()
        case (.mosques, _): GuideSearchAreaPicture()
        }
    }
}

/// A little map: streets, the blue dot, the green line running off to the Kaaba.
private struct GuideMapTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            // Streets
            Group {
                Rectangle().frame(width: 10, height: 200).offset(x: -30)
                Rectangle().frame(width: 200, height: 8).offset(y: 34)
                Rectangle().frame(width: 6, height: 200).offset(x: 44)
            }
            .foregroundStyle(Color(.systemBackground))
            // Buildings
            Group {
                RoundedRectangle(cornerRadius: 3).frame(width: 34, height: 40).offset(x: 6, y: -24)
                RoundedRectangle(cornerRadius: 3).frame(width: 24, height: 26).offset(x: -58, y: 62)
            }
            .foregroundStyle(Color.primary.opacity(0.08))
        }
        .frame(width: 150, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct GuideQiblaLine: View {
    var drawn: CGFloat = 1
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 75, y: 75))
                p.addLine(to: CGPoint(x: 128, y: 18))
            }
            .trim(from: 0, to: drawn)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            Image(systemName: "cube.fill")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .position(x: 134, y: 12)
                .opacity(drawn > 0.95 ? 1 : 0)
            Circle().fill(Color.white).frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.15), radius: 2)
                .overlay(Circle().fill(Color.blue).frame(width: 12, height: 12))
                .position(x: 75, y: 75)
        }
        .frame(width: 150, height: 150)
    }
}

/// Page 1: the line draws itself from the dot to the Kaaba.
private struct GuideLinePicture: View {
    var body: some View {
        ZStack {
            GuideMapTile()
            PhaseAnimator([0.0, 1.0]) { drawn in
                GuideQiblaLine(drawn: drawn)
            } animation: { phase in
                // The phase's delay is the hold before it: draw, rest, clear, rest.
                phase == 1 ? .easeInOut(duration: 1.2).delay(0.6) : .easeInOut(duration: 0.5).delay(2.2)
            }
        }
    }
}

/// Page 2: the map turns until the green line points straight up the phone.
private struct GuideRotatePicture: View {
    var body: some View {
        ZStack {
            PhaseAnimator([0.0, -43.0]) { angle in
                ZStack {
                    GuideMapTile()
                    GuideQiblaLine()
                }
                .rotationEffect(.degrees(angle))
                .scaleEffect(0.82)
            } animation: { angle in angle == 0 ? .easeInOut(duration: 0.9).delay(2.2) : .easeInOut(duration: 1.4).delay(0.8) }
            // The phone's edge, and "up" at the top of it.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: 150, height: 150)
            Image(systemName: "chevron.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.green)
                .offset(y: -86)
        }
    }
}

/// Page 3: the ring — the blue arrow swings round to the triangle and the ring goes green.
private struct GuideRingPicture: View {
    private let qibla = 55.0
    var body: some View {
        PhaseAnimator([-40.0, 55.0]) { heading in
            let aligned = abs(heading - qibla) < 1
            ZStack {
                Circle()
                    .stroke(aligned ? Color.green : Color.primary.opacity(0.25), lineWidth: aligned ? 3 : 1.5)
                    .frame(width: 120, height: 120)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(aligned ? Color.green : Color.primary.opacity(0.6))
                    .offset(y: -68)
                    .rotationEffect(.degrees(qibla))
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(aligned ? Color.green : Color.blue)
                    .offset(y: -16)
                    .rotationEffect(.degrees(heading))
                Circle().fill(Color.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 2)
                    .overlay(Circle().fill(Color.blue).frame(width: 10, height: 10))
            }
            .frame(width: 150, height: 150)
        } animation: { h in h == 55 ? .spring(response: 1.2, dampingFraction: 0.85).delay(0.8) : .easeInOut(duration: 0.9).delay(2.2) }
    }
}

// MARK: - Prayer spots pictures

private struct GuidePin: View {
    let color: Color
    var body: some View {
        Circle().fill(color)
            .frame(width: 13, height: 13)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    }
}

/// Pins drop in one after another, each in its score colour.
private struct GuidePinsPicture: View {
    private let pins: [(CGFloat, CGFloat, Color)] = [
        (-38, -30, .green), (22, -44, .yellow), (40, 10, .green), (-20, 26, .red), (8, 52, .gray), (-52, 58, .yellow),
    ]
    var body: some View {
        ZStack {
            GuideMapTile()
            PhaseAnimator([0, 1, 2, 3, 4, 5, 6]) { shown in
                ZStack {
                    ForEach(pins.indices, id: \.self) { i in
                        GuidePin(color: pins[i].2)
                            .offset(x: pins[i].0, y: pins[i].1 - (i < shown ? 0 : 14))
                            .opacity(i < shown ? 1 : 0)
                    }
                }
            } animation: { n in n == 0 ? .easeInOut(duration: 0.4).delay(2.2) : .spring(response: 0.4, dampingFraction: 0.7).delay(n == 1 ? 0.5 : 0.28) }
        }
    }
}

/// A cluster, and the sheet that slides up with the prayers there.
private struct GuidePinCardPicture: View {
    var body: some View {
        ZStack {
            GuideMapTile()
            PhaseAnimator([false, true]) { open in
                ZStack(alignment: .bottom) {
                    Text("4")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.green))
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                        .scaleEffect(open ? 1.2 : 1)
                        .offset(y: -78)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([("Asr", Color.yellow), ("Fajr", Color.green), ("Isha", Color.red)], id: \.0) { row in
                            HStack(spacing: 6) {
                                Circle().fill(row.1).frame(width: 6, height: 6)
                                Text(row.0).font(.system(size: 10, weight: .regular, design: .rounded))
                                Spacer()
                                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 30, height: 5)
                            }
                        }
                    }
                    .padding(10)
                    .frame(width: 130)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
                    .shadow(color: .black.opacity(0.12), radius: 4, y: -1)
                    .offset(y: open ? -8 : 80)
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } animation: { open in open ? .spring(response: 0.7, dampingFraction: 0.9).delay(0.9) : .easeInOut(duration: 0.5).delay(2.6) }
        }
    }
}

/// The five prayer chips; some switch on, and the pill reads what's shown.
private struct GuideFilterPicture: View {
    private let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    var body: some View {
        PhaseAnimator([Set<Int>(), [0], [0, 4]]) { on in
            VStack(spacing: 14) {
                Text(on.isEmpty ? "all your prayers" : on.count == 1 ? "every Fajr" : "every Fajr, Isha")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(on.isEmpty ? Color.primary : Color.green)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
                    .contentTransition(.opacity)
                HStack(spacing: 6) {
                    ForEach(names.indices, id: \.self) { i in
                        Image(systemName: prayerIcon(for: names[i]))
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(on.contains(i) ? Color.green : Color.primary.opacity(0.5))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(on.contains(i) ? Color.green.opacity(0.15) : Color(.secondarySystemBackground)))
                    }
                }
            }
            .frame(width: 150, height: 150)
        } animation: { on in .easeInOut(duration: 0.35).delay(on.isEmpty ? 2.2 : 1.3) }
    }
}

// MARK: - Mosque pictures

private struct GuideMosquePin: View {
    var body: some View {
        Image(systemName: "building.columns.fill")
            .font(.system(size: 9))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.green))
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    }
}

/// Mosque pins pop up around the blue dot.
private struct GuideMosquesPicture: View {
    private let spots: [(CGFloat, CGFloat)] = [(-44, -36), (36, -48), (48, 26), (-30, 48)]
    var body: some View {
        ZStack {
            GuideMapTile()
            Circle().fill(Color.white).frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.15), radius: 2)
                .overlay(Circle().fill(Color.blue).frame(width: 10, height: 10))
            PhaseAnimator([0, 1, 2, 3, 4]) { shown in
                ZStack {
                    ForEach(spots.indices, id: \.self) { i in
                        GuideMosquePin()
                            .offset(x: spots[i].0, y: spots[i].1)
                            .scaleEffect(i < shown ? 1 : 0.2)
                            .opacity(i < shown ? 1 : 0)
                    }
                }
            } animation: { n in n == 0 ? .easeInOut(duration: 0.4).delay(2.2) : .spring(response: 0.4, dampingFraction: 0.7).delay(n == 1 ? 0.5 : 0.3) }
        }
    }
}

/// The mosque card: the entrance, the time there (driving ⇄ walking), Directions.
private struct GuideMosqueCardPicture: View {
    var body: some View {
        PhaseAnimator([false, true]) { walking in
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(.systemGray4), Color(.systemGray6)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 44)
                    .overlay(Image(systemName: "binoculars").font(.system(size: 13, weight: .light)).foregroundStyle(.secondary))
                HStack(spacing: 5) {
                    Image(systemName: walking ? "figure.walk" : "car.fill")
                        .contentTransition(.symbolEffect(.replace))
                    Text(walking ? "18 min" : "6 min")
                        .contentTransition(.numericText())
                }
                .font(.system(size: 12, weight: .regular, design: .rounded))
                Text("Directions")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.green)
                    .frame(maxWidth: .infinity).frame(height: 24)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
            }
            .padding(12)
            .frame(width: 132)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
            .frame(width: 150, height: 150)
        } animation: { _ in .easeInOut(duration: 0.5).delay(1.6) }
    }
}

/// The map slides somewhere new and "Search this area" appears.
private struct GuideSearchAreaPicture: View {
    var body: some View {
        PhaseAnimator([false, true]) { moved in
            ZStack(alignment: .bottom) {
                GuideMapTile()
                    .offset(x: moved ? -26 : 0, y: moved ? -14 : 0)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Label("Search this area", systemImage: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(Color(.systemBackground)))
                    .shadow(color: .black.opacity(0.12), radius: 3)
                    .padding(.bottom, 10)
                    .opacity(moved ? 1 : 0)
                    .offset(y: moved ? 0 : 12)
            }
            .frame(width: 150, height: 150)
        } animation: { moved in moved ? .easeInOut(duration: 1.0).delay(0.8) : .easeInOut(duration: 0.6).delay(2.2) }
    }
}

/// Shown only while the map is turned away from its home: qibla-up in qibla mode (a green arrow
/// pointing where the qibla is on screen), north-up otherwise (a red needle). Tap → back home.
/// Reads `MapAnchor`, so only it re-renders while the map rotates.
struct MapNorthButton: View {
    var anchor: MapAnchor
    /// The qibla bearing in qibla mode (home = that heading); nil = home is north.
    let qiblaBearing: Double?
    let reset: () -> Void

    private var home: Double { qiblaBearing ?? 0 }

    private var turned: Bool {
        let d = (anchor.mapHeading - home).truncatingRemainder(dividingBy: 360)
        let a = abs(d)
        return min(a, 360 - a) > 2
    }

    var body: some View {
        if turned {
            VStack(spacing: 0) {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 0.5)
                Button(action: reset) {
                    Group {
                        if let qiblaBearing {
                            Image(systemName: "location.north.line.fill")
                                .rotationEffect(.degrees(qiblaBearing - anchor.mapHeading))
                                .mapControlIcon(tint: .green)
                        } else {
                            Image(systemName: "location.north.line.fill")
                                .rotationEffect(.degrees(-anchor.mapHeading))
                                .mapControlIcon(tint: .red.opacity(0.85))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(qiblaBearing != nil ? "Point the qibla up" : "Turn the map north-up")
            }
            .transition(.opacity)
        }
    }
}

#Preview("Qibla") { MapGuide(topic: .qibla) {} }
#Preview("Prayers") { MapGuide(topic: .prayers) {} }
#Preview("Mosques") { MapGuide(topic: .mosques) {} }
