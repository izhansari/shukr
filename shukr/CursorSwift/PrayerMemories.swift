//
//  PrayerMemories.swift
//  shukr
//
//  Memories: every prayer photo, to look back on (owner, 2026-10-07: "it to feel good for viewing memories, not so much
//  feeling like data … sleek … simple"). The page is a film strip of days (decision prayer-memories-layout, Strip 2:
//  the day's number and weekday, five squares Fajr → Isha, an empty one where there's no photo, no letters); a photo
//  zooms into a loose pile (Deck 2: "it looks like a loosely organized stack … cute and intimate and like memorabilia")
//  in the strip's order (oldest at the top of the page, newest at the bottom, like Photos): swipe left for newer, right
//  to go back; each card lies at a random nudge and tilt ("feel less computer generated"), the top one centred; a tap
//  swaps front and back; swipe down closes it back into its square. Apple's own zoom
//  transition (iOS 18 `matchedTransitionSource` / `.navigationTransition(.zoom)`), `sensoryFeedback` for the clicks.
//

import SwiftUI
import ImageIO

/// One saved photo, as Memories lists it.
struct MemoryPhoto: Identifiable, Hashable {
    let key: String       // "2026-10-07-Asr"
    var id: String { key }
    var dayKey: String { String(key.prefix(10)) }
    var name: String { String(key.dropFirst(11)) }
    /// Its place in the day, Fajr first.
    var slot: Int { ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].firstIndex(of: name) ?? 0 }
}

/// Opens Memories from anywhere (the day page's link, the ☰ menu).
@MainActor @Observable final class MemoriesPresenter {
    static let shared = MemoriesPresenter()
    var open = false
}

extension PrayerPhotos {
    /// Every saved photo, oldest first (by day, then Fajr → Isha) — the strip's reading order.
    static func all() -> [MemoryPhoto] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix("-back.jpg") }
            .map { MemoryPhoto(key: String($0.dropLast("-back.jpg".count))) }
            .sorted { $0.dayKey != $1.dayKey ? $0.dayKey < $1.dayKey : $0.slot < $1.slot }
    }

    private static let thumbs = NSCache<NSString, UIImage>()

    /// A small copy of the back photo (ImageIO's thumbnail, decoded off the main thread, cached).
    static func thumbnail(_ key: String, side: Int = 160) async -> UIImage? {
        let cacheKey = "\(key)-\(side)" as NSString
        if let hit = thumbs.object(forKey: cacheKey) { return hit }
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url(key, front: false) as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: side]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
        }.value
        if let image { thumbs.setObject(image, forKey: cacheKey) }
        return image
    }
}

// MARK: - The page

struct MemoriesPage: View {
    let onClose: () -> Void
    @Namespace private var zoom
    @State private var photos: [MemoryPhoto] = []
    @State private var opened: MemoryPhoto?
    /// The photo on top of the pile, so closing zooms back into its own square.
    @State private var top: String = ""

    /// Days with at least one photo, oldest first, grouped by month (newest at the bottom, like Photos).
    private var months: [(title: String, days: [(dayKey: String, photos: [MemoryPhoto])])] {
        let byDay = Dictionary(grouping: photos, by: \.dayKey)
        let days = byDay.keys.sorted(by: <).map { ($0, byDay[$0] ?? []) }
        let byMonth = Dictionary(grouping: days, by: { String($0.0.prefix(7)) })
        return byMonth.keys.sorted(by: <).map { month in
            (Self.monthTitle(month), (byMonth[month] ?? []).sorted { $0.0 < $1.0 })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if photos.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 34, weight: .light))
                        Text("No photos yet").font(.headline)
                        Text("After you mark a prayer, the pill's camera saves one here.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 140).padding(.horizontal, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(months, id: \.title) { month in
                            Text(month.title)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .padding(.top, 8)
                            ForEach(month.days, id: \.dayKey) { day in
                                dayRow(day.dayKey, day.photos)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .defaultScrollAnchor(.bottom)
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back")
                }
            }
            .navigationDestination(item: $opened) { start in
                MemoriesDeck(photos: photos, start: start, top: $top)
                    .navigationTransition(.zoom(sourceID: top.isEmpty ? start.key : top, in: zoom))
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .task(id: PrayerPhotoRevision.shared.value) { photos = PrayerPhotos.all() }
    }

    /// "6 / Tue", then five squares, Fajr → Isha.
    private func dayRow(_ dayKey: String, _ dayPhotos: [MemoryPhoto]) -> some View {
        let date = Self.parse(dayKey)
        return HStack(spacing: 14) {
            VStack(spacing: 1) {
                Text(date.map { "\(Calendar.current.component(.day, from: $0))" } ?? "")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(date.map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(width: 38)
            HStack(spacing: 7) {
                ForEach(0..<5, id: \.self) { slot in
                    if let photo = dayPhotos.first(where: { $0.slot == slot }) {
                        MemoryThumb(key: photo.key)
                            .matchedTransitionSource(id: photo.key, in: zoom) { source in
                                source.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .onTapGesture { top = photo.key; opened = photo }
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                            .frame(width: 52, height: 52)
                    }
                }
            }
        }
    }

    static func parse(_ dayKey: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: dayKey)
    }

    static func monthTitle(_ month: String) -> String {
        parse(month + "-01").map { $0.formatted(.dateTime.month(.wide).year()) } ?? month
    }
}

/// A day's square: the back photo, small, a rounded square.
private struct MemoryThumb: View {
    let key: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.primary.opacity(0.08) }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: key) { image = await PrayerPhotos.thumbnail(key) }
        .accessibilityLabel(PrayerPhotos.caption(key))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - The pile

/// The loose pile (Deck 2), in the strip's order: older under, newer on top. `index` is the photo on top, centred and
/// nearly straight; the ones already seen lie under it, each at its own random nudge and tilt, so it reads as a pile
/// (owner: "make it so the stack looks like a stack … the focused one always comes back to center"). Swipe left: the
/// next newer one comes in from the right and lands on top. Swipe right: the top one goes back off to the right.
struct MemoriesDeck: View {
    let photos: [MemoryPhoto]
    let start: MemoryPhoto
    @Binding var top: String
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var drag: CGFloat = 0
    /// A drag down: the pile follows the finger and shrinks a little, then closes into its square.
    @State private var down: CGFloat = 0
    /// Which way this drag went, fixed by its first move.
    @State private var vertical: Bool?
    /// Where each card lies in the pile, picked at random the first time it's needed (owner: "just do random angles …
    /// feel more hand made"); not stored.
    @State private var lie: [String: Lie] = [:]
    @State private var swapped: Set<String> = []

    struct Lie { var dx: CGFloat; var dy: CGFloat; var tilt: Double }

    /// How many seen cards show under the top one.
    private static let pileDepth = 4

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 72, 360)
            let current = photos.indices.contains(index) ? photos[index] : nil
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                ZStack {
                    ForEach(cardIndices, id: \.self) { i in
                        card(i, width: width, screen: geo.size.width)
                    }
                }
                .frame(width: geo.size.width, height: width + 30)
                .contentShape(Rectangle())
                .offset(y: max(down, 0))
                .scaleEffect(1 - min(max(down, 0) / 1600, 0.2))
                .gesture(pileDrag(screen: geo.size.width))
                if let current {
                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: prayerIcon(for: current.name)).font(.system(size: 17))
                            Text(current.name).font(.system(size: 22, weight: .medium, design: .rounded))
                        }
                        Text(MemoriesPage.parse(current.dayKey)?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? "")
                            .font(.system(size: 15, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: index)
                    .opacity(1 - min(max(down, 0) / 120, 1))
                }
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.regularMaterial))
            }
            .accessibilityLabel("Close")
            .padding(.leading, 20).padding(.top, 8)
        }
        .sensoryFeedback(.selection, trigger: index)
        .onChange(of: index) { _, i in if photos.indices.contains(i) { top = photos[i].key } }
        .onAppear {
            index = photos.firstIndex(of: start) ?? 0
            pickLies()
        }
    }

    /// The pile under the top one, the top one, and the next newer one waiting off to the right.
    private var cardIndices: [Int] {
        Array(max(index - Self.pileDepth, 0)...min(index + 1, photos.count - 1))
    }

    @ViewBuilder
    private func card(_ i: Int, width: CGFloat, screen: CGFloat) -> some View {
        let key = photos[i].key
        let l = lie[key] ?? Lie(dx: 0, dy: 0, tilt: 0)
        let (x, y, angle): (CGFloat, CGFloat, Double) = {
            if i > index {
                // Waiting off to the right; a swipe left pulls it in.
                let x = screen + min(drag, 0)
                return (x, 0, l.tilt * 0.3 + Double(x) / 40)
            } else if i == index {
                // On top: centred, nearly straight; a swipe right takes it back off to the right.
                let x = max(drag, 0)
                return (x, 0, l.tilt * 0.3 + Double(x) / 40)
            } else {
                return (l.dx, l.dy, l.tilt)
            }
        }()
        MemoryCard(key: key, width: width, swapped: swapped.contains(key))
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .zIndex(Double(i))
            .allowsHitTesting(i == index)
            .onTapGesture {
                withAnimation(.snappy(duration: 0.25)) {
                    if swapped.contains(key) { swapped.remove(key) } else { swapped.insert(key) }
                }
            }
    }

    private func pileDrag(screen: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if vertical == nil {
                    vertical = abs(value.translation.height) > abs(value.translation.width)
                }
                if vertical == true { down = value.translation.height; return }
                let t = value.translation.width
                // At either end the pile gives a little and comes back.
                if t < 0, index >= photos.count - 1 { drag = t / 6 } else if t > 0, index == 0 { drag = 0 } else { drag = t }
            }
            .onEnded { value in
                defer { vertical = nil }
                if vertical == true {
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { down = 0 }
                    }
                    return
                }
                let far = value.translation.width, flung = value.predictedEndTranslation.width
                let settle = Animation.spring(response: 0.42, dampingFraction: 0.82)
                if (far < -90 || flung < -240), index < photos.count - 1 {
                    // The newer one lands on top; the old top settles into the pile.
                    withAnimation(settle) { index += 1; drag = 0 }
                    pickLies()
                } else if (far > 90 || flung > 240), index > 0 {
                    // The top one goes back off to the right; the one under it comes up to the centre.
                    withAnimation(settle) { index -= 1; drag = 0 }
                    pickLies()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = 0 }
                }
            }
    }

    /// A random lie for each card near the top, the first time it shows.
    private func pickLies() {
        let around = max(index - Self.pileDepth - 1, 0)..<min(index + 3, photos.count)
        for i in around where lie[photos[i].key] == nil {
            lie[photos[i].key] = Lie(dx: .random(in: -22...22), dy: .random(in: -14...14), tilt: .random(in: -9...9))
        }
    }
}

/// One card in the pile: the photo the card's way (rounded square, front inset), with a soft shadow.
private struct MemoryCard: View {
    let key: String
    let width: CGFloat
    let swapped: Bool
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)

    var body: some View {
        PrayerPhotoFace(back: swapped ? images.front ?? images.back : images.back,
                        front: swapped ? images.back : images.front,
                        width: width)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .task(id: key) { images = await PrayerPhotos.load(key) }
    }
}
