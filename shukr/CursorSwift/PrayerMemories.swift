//
//  PrayerMemories.swift
//  shukr
//
//  Memories: every prayer photo, to look back on (owner, 2026-10-07: "it to feel good for viewing memories, not so much
//  feeling like data … sleek … simple"). The page is a film strip of days (decision prayer-memories-layout, Strip 2:
//  the day's number and weekday, five squares Fajr → Isha, an empty one where there's no photo, no letters); a photo
//  zooms into a loose pile (Deck 2: "it looks like a loosely organized stack … cute and intimate and like memorabilia")
//  — flick the top one left for older, pull one back with a swipe right; each card lands at a random tilt ("feel less
//  computer generated"); a tap swaps front and back; swipe down closes it back into its square. Apple's own zoom
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
    /// Every saved photo, newest first (by day, then Isha → Fajr).
    static func all() -> [MemoryPhoto] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix("-back.jpg") }
            .map { MemoryPhoto(key: String($0.dropLast("-back.jpg".count))) }
            .sorted { $0.dayKey != $1.dayKey ? $0.dayKey > $1.dayKey : $0.slot > $1.slot }
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

    /// Days with at least one photo, newest first, grouped by month.
    private var months: [(title: String, days: [(dayKey: String, photos: [MemoryPhoto])])] {
        let byDay = Dictionary(grouping: photos, by: \.dayKey)
        let days = byDay.keys.sorted(by: >).map { ($0, byDay[$0] ?? []) }
        let byMonth = Dictionary(grouping: days, by: { String($0.0.prefix(7)) })
        return byMonth.keys.sorted(by: >).map { month in
            (Self.monthTitle(month), (byMonth[month] ?? []).sorted { $0.0 > $1.0 })
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

/// The loose pile (Deck 2). `index` is the photo on top; the next two peek out under it. Flick the top one left to put
/// it away (older); swipe right to pull the one before back on top (newer).
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
    /// Random tilts, picked as a card first shows (owner: "just do random angles … feel more hand made").
    @State private var tilts: [String: Double] = [:]
    @State private var swapped: Set<String> = []

    private func tilt(_ key: String) -> Double { tilts[key] ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 72, 360)
            let current = photos.indices.contains(index) ? photos[index] : nil
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                ZStack {
                    // Under the top one: the next two, in their tilts.
                    ForEach(Array(stackKeys.enumerated().reversed()), id: \.element) { depth, key in
                        let isTop = depth == 0
                        MemoryCard(key: key, width: width, swapped: swapped.contains(key))
                            .rotationEffect(.degrees(tilt(key) + (isTop ? Double(drag) / 18 : 0)))
                            .offset(x: isTop ? min(drag, 0) : 0, y: isTop ? 0 : CGFloat(depth) * 4)
                            .scaleEffect(isTop ? 1 : 1 - CGFloat(depth) * 0.03)
                            .zIndex(Double(10 - depth))
                            .onTapGesture {
                                guard isTop else { return }
                                withAnimation(.snappy(duration: 0.25)) {
                                    if swapped.contains(key) { swapped.remove(key) } else { swapped.insert(key) }
                                }
                            }
                    }
                    // Pulled back: the newer one comes in from the right, over the pile.
                    if drag > 0, index > 0 {
                        let key = photos[index - 1].key
                        MemoryCard(key: key, width: width, swapped: swapped.contains(key))
                            .rotationEffect(.degrees(tilt(key)))
                            .offset(x: geo.size.width - drag * 1.2)
                            .zIndex(20)
                    }
                }
                .offset(y: max(down, 0))
                .scaleEffect(1 - min(max(down, 0) / 1600, 0.2))
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            if vertical == nil {
                                vertical = abs(value.translation.height) > abs(value.translation.width)
                            }
                            if vertical == true { down = value.translation.height } else { drag = value.translation.width }
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
                            if (far < -110 || flung < -260), index < photos.count - 1 {
                                // Put it away: off to the left, then the next is on top.
                                withAnimation(.easeIn(duration: 0.18)) { drag = -geo.size.width * 1.2 }
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(180))
                                    var quiet = Transaction(); quiet.disablesAnimations = true
                                    withTransaction(quiet) { index += 1; drag = 0 }
                                    pickTilts()
                                }
                            } else if (far > 110 || flung > 260), index > 0 {
                                // Pull one back on top.
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { index -= 1; drag = 0 }
                                pickTilts()
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = 0 }
                            }
                        }
                )
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
            pickTilts()
        }
    }

    /// The top card and the two under it.
    private var stackKeys: [String] {
        (index..<min(index + 3, photos.count)).map { photos[$0].key }
    }

    /// A new random tilt for each card as it joins the pile (the one on top a touch straighter).
    private func pickTilts() {
        let around = max(index - 1, 0)..<min(index + 4, photos.count)
        for i in around where tilts[photos[i].key] == nil {
            tilts[photos[i].key] = Double.random(in: -7...7)
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
