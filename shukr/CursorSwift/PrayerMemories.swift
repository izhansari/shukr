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
        return Set(files.compactMap(key(fromFile:))).map { MemoryPhoto(key: $0) }
            .sorted { $0.dayKey != $1.dayKey ? $0.dayKey < $1.dayKey : $0.slot < $1.slot }
    }

    private static let thumbs = NSCache<NSString, UIImage>()

    /// A small copy of the back photo (ImageIO's thumbnail, decoded off the main thread, cached).
    static func thumbnail(_ key: String, side: Int = 160) async -> UIImage? {
        let cacheKey = "\(key)-\(side)-\(PrayerPhotoMain.selfieIsMain(key))" as NSString
        if let hit = thumbs.object(forKey: cacheKey) { return hit }
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(mainURL(key) as CFURL, nil) else { return nil }
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
    /// The squares that fly into their day's or month's stack on a pinch, and back.
    @Namespace private var pinch
    @State private var photos: [MemoryPhoto] = []
    /// The pile, open from this photo.
    @State private var deckStart: MemoryPhoto?
    /// What it zoomed out of (a day's stack or a prayer's square), and back into on close — fixed while it's open
    /// (owner: "prioritize being clean … apple documented apis": the system's zoom transition, nothing hand-made).
    @State private var deckSource = ""
    @Namespace private var zoom
    @State private var showSettings = false

    /// Three levels, like Photos' Years / Months / Days (owner: "the most granular is every single prayer photo. The one
    /// level up is every single day is a stack. And then the next level up is every single month as a stack").
    enum Level: Int, CaseIterable, Identifiable {
        case months, days, prayers
        var id: Int { rawValue }
        var title: String { ["Months", "Days", "Prayers"][rawValue] }
    }
    @State private var level: Level = .days
    /// The id at the top of each level's screen (a month "2026-10" or, on Prayers, a day "2026-10-06"); a level opens
    /// there when it was picked from another, else at the bottom (today).
    @State private var tops: [Level: String] = [:]
    @State private var pinned: Set<Level> = []

    typealias Day = (dayKey: String, photos: [MemoryPhoto])
    typealias Month = (id: String, title: String, days: [Day], photos: [MemoryPhoto])

    /// Days with at least one photo, oldest first, grouped by month (newest at the bottom, like Photos).
    private var months: [Month] {
        let byDay = Dictionary(grouping: photos, by: \.dayKey)
        let days = byDay.keys.sorted(by: <).map { ($0, byDay[$0] ?? []) }
        let byMonth = Dictionary(grouping: days, by: { String($0.0.prefix(7)) })
        return byMonth.keys.sorted(by: <).map { month in
            let monthDays = (byMonth[month] ?? []).sorted { $0.0 < $1.0 }
            return (month, Self.monthTitle(month), monthDays, monthDays.flatMap(\.1))
        }
    }

    var body: some View {
        NavigationStack {
            // One scroll view per level, swapped whole: a shared one scrolled under the change and the squares never
            // flew into their stacks.
            Group {
                if photos.isEmpty {
                    ScrollView {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 34, weight: .light))
                            Text("No photos yet").font(.headline)
                            Text("After you mark a prayer, the pill's camera saves one here.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 140).padding(.horizontal, 40)
                    }
                } else {
                    switch level {
                    case .months: levelScroll(.months) { monthStacks }
                    case .days: levelScroll(.days) { dayStacks }
                    case .prayers: levelScroll(.prayers) { prayerStrips }
                    }
                }
            }
            .simultaneousGesture(
                MagnifyGesture().onEnded { value in
                    if value.magnification < 0.8, let up = Level(rawValue: level.rawValue - 1) { go(up) }
                    if value.magnification > 1.25, let down = Level(rawValue: level.rawValue + 1) { go(down) }
                }
            )
            .safeAreaInset(edge: .bottom) {
                if !photos.isEmpty {
                    // For anyone who never finds the pinch (Photos' own control, at the bottom).
                    Picker("Show", selection: Binding(get: { level }, set: { go($0) })) {
                        ForEach(Level.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 4)
                }
            }
            .sensoryFeedback(.selection, trigger: level)
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Photo settings")
                }
            }
            .sheet(isPresented: $showSettings) { MemoriesSettings() }
        }
        .fullScreenCover(item: $deckStart) { start in
            NavigationStack { MemoriesDeck(photos: photos, start: start) }
                .navigationTransition(.zoom(sourceID: deckSource, in: zoom))
        }
        .task(id: PrayerPhotoRevision.shared.value) { photos = PrayerPhotos.all() }
    }

    private func levelScroll<Content: View>(_ l: Level, @ViewBuilder content: () -> Content) -> some View {
        ScrollView { content() }
            .scrollPosition(id: Binding(get: { tops[l] }, set: { tops[l] = $0 }), anchor: .top)
            .defaultScrollAnchor(pinned.contains(l) ? .top : .bottom)
    }

    /// To another level, opening at `id` (a tapped stack), else at the month that's on screen now.
    private func go(_ new: Level, at id: String? = nil) {
        guard new != level else { return }
        if let target = id ?? tops[level].map({ String($0.prefix(7)) }) {
            tops[new] = target
            pinned.insert(new)
        } else {
            tops[new] = nil
            pinned.remove(new)
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { level = new }
    }

    private func openDeck(_ photo: MemoryPhoto, from source: String) {
        deckSource = source
        deckStart = photo
    }

    private func monthHeader(_ month: Month) -> some View {
        Text(month.title)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every prayer: a row per day, five squares.
    private var prayerStrips: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(months, id: \.id) { month in
                monthHeader(month).id(month.id)
                ForEach(month.days, id: \.dayKey) { day in
                    dayRow(day.dayKey, day.photos).id(day.dayKey)
                }
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    /// Each month as a calendar, a week to a row (owner: "organized the same way a calendar would be"); a day with photos
    /// is a small pile, a tap opens that day's prayers; a day without is just its number, faint.
    private var dayStacks: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(months, id: \.id) { month in
                monthHeader(month).id(month.id)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 12) {
                    ForEach(Self.weekdayLetters.indices, id: \.self) { i in
                        Text(Self.weekdayLetters[i])
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(Self.calendarCells(month.id).enumerated()), id: \.offset) { _, cell in
                        if let dayKey = cell {
                            calendarDay(dayKey, month.days.first { $0.dayKey == dayKey }?.photos ?? [])
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                }
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func calendarDay(_ dayKey: String, _ dayPhotos: [MemoryPhoto]) -> some View {
        let number = Text(String(Int(dayKey.suffix(2)) ?? 0)).font(.system(size: 11, weight: .medium, design: .rounded))
        if dayPhotos.isEmpty {
            VStack(spacing: 4) {
                Color.clear.frame(height: 40)
                number.foregroundStyle(.tertiary)
            }
        } else {
            Button { if let newest = dayPhotos.last { openDeck(newest, from: dayKey) } } label: {
                VStack(spacing: 4) {
                    stack(dayPhotos, side: 38, corner: 10).frame(height: 40)
                        .matchedTransitionSource(id: dayKey, in: zoom)
                    number.foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The week's day letters, from the calendar's first weekday (Sunday in the US).
    private static let weekdayLetters: [String] = {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
    }()

    /// A month's cells, week by week: nil before the 1st, then each day's key up to today (days still to come aren't
    /// shown — owner).
    private static func calendarCells(_ month: String) -> [String?] {
        let cal = Calendar.current
        guard let first = parse(month + "-01"), let days = cal.range(of: .day, in: .month, for: first)?.count else { return [] }
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        // The local date (the ISO style alone is in UTC: after 8 PM in New York it was already tomorrow).
        let today = Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day().dateSeparator(.dash))
        return Array(repeating: nil, count: lead)
            + (1...days).map { String(format: "%@-%02d", month, $0) }.filter { $0 <= today }
    }

    /// Each month as a small pile, with the month and how many under it; a tap opens its days.
    private var monthStacks: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 28) {
            ForEach(months, id: \.id) { month in
                Button { go(.days, at: month.id) } label: {
                    VStack(spacing: 12) {
                        stack(month.photos, side: 118, corner: 22).frame(height: 140)
                        VStack(spacing: 2) {
                            Text(month.title).font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(month.photos.count == 1 ? "1 photo" : "\(month.photos.count) photos")
                                .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .id(month.id)
            }
        }
        .scrollTargetLayout()
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    /// The newest three, loose, the newest straight on top; the squares fly in and out of it (`pinch`).
    private func stack(_ photos: [MemoryPhoto], side: CGFloat, corner: CGFloat) -> some View {
        let shown = Array(photos.suffix(3))
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.key) { n, photo in
                let onTop = n == shown.count - 1
                MemoryThumb(key: photo.key, side: Int(side * 3), corner: corner)
                    .matchedGeometryEffect(id: photo.key, in: pinch)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .rotationEffect(.degrees(onTop ? 0 : Self.looseTilt(photo.key)))
                    .offset(x: onTop ? 0 : Self.looseNudge(photo.key) * side / 118,
                            y: CGFloat(shown.count - 1 - n) * -3)
            }
        }
    }

    /// A loose angle and nudge for a card in a stack, the same each time it's drawn.
    private static func looseTilt(_ key: String) -> Double { Double(abs(key.hashValue) % 19) - 9 }
    private static func looseNudge(_ key: String) -> CGFloat { CGFloat(abs(key.hashValue / 19) % 25) - 12 }

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
                            .matchedGeometryEffect(id: photo.key, in: pinch)
                            .frame(width: 52, height: 52)
                            .matchedTransitionSource(id: photo.key, in: zoom) { source in
                                source.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .onTapGesture { openDeck(photo, from: photo.key) }
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

/// A photo's back picture as a rounded square that fills whatever frame it's given (so a pinch can grow it into its
/// month's stack and back).
private struct MemoryThumb: View {
    let key: String
    var side: Int = 160
    var corner: CGFloat = 12
    @State private var image: UIImage?
    var body: some View {
        Color.primary.opacity(0.08)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .task(id: "\(key)-\(PrayerPhotoMain.shared.isSelfie(key))") { image = await PrayerPhotos.thumbnail(key, side: side) }
            .accessibilityLabel(PrayerPhotos.caption(key))
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - The pile

/// The loose pile (Deck 2), in the strips' order: older under, newer on top. `index` is the photo on top, centred and
/// nearly straight; the ones already seen lie under it, each at its own random nudge and tilt (owner: "make it so the
/// stack looks like a stack … the focused one always comes back to center"). Swipe left: the next newer one comes in
/// from the right and lands on top; swipe right: the top one goes back off to the right. Just the photos, the prayer and
/// day under them (owner: "no text or badges in the photo at time of viewing"); Share opens the share page. Presented
/// full screen with the system's zoom from the day or square it was opened from.
struct MemoriesDeck: View {
    let photos: [MemoryPhoto]
    let start: MemoryPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var index: Int
    @State private var drag: CGFloat = 0
    /// A drag down: the pile follows the finger and shrinks a little, then closes.
    @State private var down: CGFloat = 0
    /// Which way this drag went, fixed by its first move.
    @State private var vertical: Bool?
    /// Where each card lies in the pile, picked at random the first time it's needed (owner: "just do random angles …
    /// feel more hand made"); not stored.
    @State private var lie: [String: Lie]
    @State private var sharing: String?

    struct Lie { var dx: CGFloat; var dy: CGFloat; var tilt: Double }

    /// How many seen cards show under the top one.
    private static let pileDepth = 4

    init(photos: [MemoryPhoto], start: MemoryPhoto) {
        self.photos = photos
        self.start = start
        let first = photos.firstIndex(of: start) ?? 0
        _index = State(initialValue: first)
        _lie = State(initialValue: Self.lies(around: first, in: photos, keeping: [:]))
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 72, 360)
            let current = photos.indices.contains(index) ? photos[index] : nil
            VStack(spacing: 26) {
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
                // Share and ✕ under it, the grey circles of a photo opened from the hold editor (owner). Always there,
                // never redrawn per photo: the share page makes the picture.
                HStack(spacing: 18) {
                    Button { if photos.indices.contains(index) { sharing = photos[index].key } } label: {
                        circleIcon("square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    Button { dismiss() } label: { circleIcon("xmark") }
                        .accessibilityLabel("Close")
                }
                .buttonStyle(.plain)
                .opacity(down > 10 ? 0 : 1)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $sharing) { key in PrayerPhotoShareComposer(key: key) }
        .sensoryFeedback(.selection, trigger: index)
        .onAppear { PrayerPhotoViewing.shared.opened() }
        .onDisappear { PrayerPhotoViewing.shared.closed() }
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 50)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
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
        MemoryCard(key: key, width: width)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .zIndex(Double(i))
            .allowsHitTesting(i == index)
            .onTapGesture {
                // The other picture becomes the main one, and stays so (owner).
                triggerSomeVibration(type: .light)
                PrayerPhotoMain.shared.toggle(key)
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
    private func pickLies() { lie = Self.lies(around: index, in: photos, keeping: lie) }

    private static func lies(around index: Int, in photos: [MemoryPhoto], keeping: [String: Lie]) -> [String: Lie] {
        var lie = keeping
        let around = max(index - pileDepth - 1, 0)..<min(index + 3, photos.count)
        for i in around where lie[photos[i].key] == nil {
            lie[photos[i].key] = Lie(dx: .random(in: -22...22), dy: .random(in: -14...14), tilt: .random(in: -9...9))
        }
        return lie
    }
}

/// One card in the pile: the photo as it is (rounded square, the other picture in the corner), no text on it.
private struct MemoryCard: View {
    let key: String
    let width: CGFloat
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)

    var body: some View {
        let selfie = PrayerPhotoMain.shared.isSelfie(key)
        PrayerPhotoFace(back: images.back, front: images.front, width: width)
            .task(id: key) { images = await PrayerPhotos.load(key) }
            .onChange(of: selfie) { _, _ in
                withAnimation(.snappy(duration: 0.25)) { images = (images.front, images.back) }
            }
    }
}

/// Share: the picture that will be sent, with what goes on it (owner: "shukr and prayer name and date always stay. but
/// give them option to add location, prayer score as progress ring, choose primary pic by tapping the image").
struct PrayerPhotoShareComposer: View {
    let key: String
    @Environment(\.modelContext) private var context
    @AppStorage(PrayerPhotos.showPlaceKey) private var showPlaceDefault = false
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)
    @State private var place: String?
    @State private var score: Double?
    @State private var addPlace = false
    @State private var addScore = false
    @State private var picture: UIImage?
    @State private var looked = false

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 48, 420)
            ScrollView {
                VStack(spacing: 22) {
                    framed(width: width)
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                        .onTapGesture {
                            guard images.front != nil else { return }
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy(duration: 0.25)) { images = (images.front, images.back) }
                            PrayerPhotoMain.shared.toggle(key)
                        }
                    if images.front != nil {
                        Text("Tap the photo to choose the main picture")
                            .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        option("Location", detail: looked && place == nil ? "Not recorded for this prayer" : place,
                               isOn: $addPlace, enabled: place != nil)
                        Divider().padding(.leading, 16)
                        option("Prayer score", detail: score.map { PrayerScoring.summary(for: $0) } ?? (looked ? "Not marked" : nil),
                               isOn: $addScore, enabled: score != nil)
                    }
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    .padding(.horizontal, 24)
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Group {
                if let picture {
                    ShareLink(item: Image(uiImage: picture),
                              preview: SharePreview(PrayerPhotos.caption(key), image: Image(uiImage: picture))) {
                        shareLabel
                    }
                } else {
                    shareLabel.opacity(0.5)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 8)
        }
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            images = await PrayerPhotos.load(key)
            score = PrayerPhotos.score(for: key, in: context)
            place = await PrayerPhotos.place(for: key, in: context)
            #if DEBUG
            // `-demoShareScore 0.86`: a score and a place for the stand-in photos (no prayer rows behind them).
            let demo = UserDefaults.standard.double(forKey: "demoShareScore")
            if demo > 0 { score = score ?? demo; place = place ?? "Masjid Al-Noor" }
            #endif
            addPlace = showPlaceDefault && place != nil
            #if DEBUG
            if demo > 0 { addPlace = true; addScore = true }   // the simulator's taps miss Toggles
            #endif
            looked = true
        }
        // The picture that's sent, made again only when what's on it changes (kept on screen meanwhile).
        .task(id: "\(addPlace)|\(addScore)|\(images.back?.hash ?? 0)") { render() }
    }

    private func framed(width: CGFloat) -> some View {
        PrayerPhotoFramed(back: images.back, front: images.front, key: key,
                          place: addPlace ? place : nil, score: addScore ? score : nil, width: width)
    }

    private var shareLabel: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Capsule().fill(Color.sage))
    }

    private func option(_ title: String, detail: String?, isOn: Binding<Bool>, enabled: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
        .disabled(!enabled)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @MainActor private func render() {
        guard images.back != nil else { return }
        let renderer = ImageRenderer(content: framed(width: 1080 / 3).padding(18))
        renderer.scale = 3
        if let image = renderer.uiImage { picture = image }
    }
}

/// Memories' own settings (owner: "put the settings for memories and photos inside this page").
struct MemoriesSettings: View {
    @AppStorage(PrayerPhotos.showPlaceKey) private var showPlace = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Show where adds the place under your photos, and to the ones you share.")) {
                    Toggle("Show where", isOn: $showPlace)
                }
                Section(footer: Text("Your photos stay on your iPhone, and in its backup.")) {
                    PrayerPhotoStorageRow()
                }
            }
            .navigationTitle("Photo settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
