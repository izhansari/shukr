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
import SwiftData
import CoreLocation
import MapKit

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

    private static let thumbs: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// Two sizes only — 180 px for the squares and day piles, 360 px for the month piles — so switching levels finds
    /// them already decoded (each level asking its own size missed the cache and decoded mid-animation).
    private static func thumbSide(_ side: Int) -> Int { side <= 180 ? 180 : 360 }

    private static func thumbKey(_ key: String, _ side: Int) -> NSString {
        "\(key)-\(thumbSide(side))-\(PrayerPhotoMain.selfieIsMain(key))" as NSString
    }

    /// Already decoded? (A square drawn again shows its picture from the first frame.)
    static func cachedThumbnail(_ key: String, side: Int = 180) -> UIImage? { thumbs.object(forKey: thumbKey(key, side)) }

    /// A small copy of the back photo (ImageIO's thumbnail, decoded off the main thread, cached).
    static func thumbnail(_ key: String, side: Int = 180) async -> UIImage? {
        let side = thumbSide(side)
        let cacheKey = thumbKey(key, side)
        if let hit = thumbs.object(forKey: cacheKey) { return hit }
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(mainURL(key) as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: side]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
        }.value
        if let image { thumbs.setObject(image, forKey: cacheKey, cost: side * side * 4) }
        return image
    }
}

// MARK: - The page

/// Pushed like 99 Names (decision swipe-back-pages A: a full-screen cover never swiped back), the system's back button.
struct MemoriesPage: View {
    /// The squares that fly into their day's or month's stack on a pinch, and back.
    @Namespace private var pinch
    @State private var photos: [MemoryPhoto] = []
    /// The pile, open from this photo.
    @State private var deckStart: MemoryPhoto?
    /// What it zoomed out of (a day's stack or a prayer's square), and back into on close — fixed while it's open
    /// (owner: "prioritize being clean … apple documented apis": the system's zoom transition, nothing hand-made).
    /// The pile's backdrop and its other parts, faded in after the photo starts flying out.
    @State private var deckShown = false
    /// Closing: the pile gathers into its top card before that card flies home.
    @State private var folding = false
    /// The one photo in flight between its square and the pile (owner: "only take the image back into that square"):
    /// a single face moved and scaled, the page frosted behind it like the hold editor's photo.
    @State private var flight: Flight?
    /// Where the squares and the day piles sit on screen, and the pile's top card — not observed, so scrolling the page
    /// never redraws it.
    @State private var frames = FrameBook()

    struct Flight {
        var key: String
        var rect: CGRect
        var images: (back: UIImage?, front: UIImage?)
        var opacity: Double = 1
    }

    final class FrameBook {
        var frames: [String: CGRect] = [:]
        var deckTop: CGRect?
        var opening = false
        var months: (signature: String, value: [Month])?
        /// The newest flight animation; an older one's completion leaves the flight alone.
        var flightToken = UUID()
    }
    @State private var showSettings = false

    // MARK: Search (decision memories-finding C): a magnifying glass beside the levels opens a field at the bottom, like
    // Apple Music's; words match notes, masjids, places, prayers and months (Gregorian and Hijri); chips filter.
    @Environment(\.modelContext) private var context
    @State private var searching = false
    @State private var query = ""
    @State private var filters: Set<SearchFilter> = []
    @State private var searchIndex: [String: SearchEntry] = [:]
    @State private var placeNamesLearned = 0
    @FocusState private var searchFocused: Bool

    enum SearchFilter: String, CaseIterable, Identifiable {
        case favorites = "Favorites", jumuah = "Jumu'ah", masjid = "At a masjid", note = "With a note"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .favorites: "heart.fill"
            case .jumuah: "building.columns"
            case .masjid: "mappin.and.ellipse"
            case .note: "text.quote"
            }
        }
    }

    struct SearchEntry { var text: String; var jumuah: Bool; var masjid: Bool; var note: Bool; var snippet: String? }

    var hasPhotos: Bool { !photos.isEmpty }

    private static var glassBar: Bool {
        if #available(iOS 26.0, *) { return true } else { return false }
    }

    /// The search field in the glass bottom bar.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Notes, places, prayers, months", text: $query)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: max(UIScreen.main.bounds.width - 130, 180))
    }

    private var filtering: Bool {
        searching && (!query.trimmingCharacters(in: .whitespaces).isEmpty || !filters.isEmpty)
    }

    /// What the levels and the pile show: everything, or the matches while searching.
    private var visible: [MemoryPhoto] { filtering ? photos.filter(matches) : photos }

    private func matches(_ photo: MemoryPhoto) -> Bool {
        let entry = searchIndex[photo.key]
        if filters.contains(.favorites), !PrayerPhotoFavorites.shared.contains(photo.key) { return false }
        if filters.contains(.jumuah), entry?.jumuah != true { return false }
        if filters.contains(.masjid), entry?.masjid != true { return false }
        if filters.contains(.note), entry?.note != true { return false }
        let words = Self.fold(query).split(separator: " ")
        guard !words.isEmpty else { return true }
        let text = entry?.text ?? Self.fold(photo.name)
        return words.allSatisfy { text.contains($0) }
    }

    /// Lowercase, no accents or apostrophes — "Jumu'ah", "jumuah" and "JUMUAH" all match.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "ʻ", with: "").replacingOccurrences(of: "ʿ", with: "")
    }

    /// What each photo can be found by, from what's already on the phone: its prayer (masjid, Jumu'ah, the place's name
    /// once looked up), its note, its day in both calendars.
    private func buildIndex() {
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted }))) ?? []
        var byKey: [String: PrayerModel] = [:]
        for row in rows { byKey["\(row.dayKey)-\(row.name)"] = row }
        let gregorian = DateFormatter()
        gregorian.dateFormat = "EEEE MMMM d yyyy"
        let hijri = DateFormatter()
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        hijri.dateFormat = "MMMM y"
        var spots: [CLLocationCoordinate2D] = []
        var index: [String: SearchEntry] = [:]
        for photo in photos {
            let row = byKey[photo.key]
            var parts = [photo.name]
            if let date = Self.parse(photo.dayKey) {
                parts.append(gregorian.string(from: date))
                parts.append(hijri.string(from: date))
            }
            let note = PrayerPhotos.note(photo.key)
            if let note { parts.append(note) }
            let jumuah = row?.isJumuah ?? false
            if jumuah { parts.append("jumuah jummah friday") }
            let masjid = row.flatMap { ($0.mosqueName ?? "").isEmpty ? nil : $0.mosqueName }
            if let masjid { parts.append(masjid + " masjid mosque") }
            if let lat = row?.latPrayedAt, let lon = row?.longPrayedAt {
                let spot = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                spots.append(spot)
                if let place = PrayerPlaceNames.name(spot) { parts.append(place) }
            }
            let place = row.flatMap { r in r.latPrayedAt.flatMap { lat in r.longPrayedAt.flatMap {
                PrayerPlaceNames.name(CLLocationCoordinate2D(latitude: lat, longitude: $0)) } } }
            index[photo.key] = SearchEntry(text: Self.fold(parts.joined(separator: " ")), jumuah: jumuah,
                                           masjid: masjid != nil, note: note != nil,
                                           snippet: note.map { $0.replacingOccurrences(of: "\n", with: " ") } ?? masjid ?? place)
        }
        searchIndex = index
        PrayerPlaceNames.fill(spots) { placeNamesLearned += 1 }
    }

    private func openSearch() {
        pinned.remove(level)
        tops[level] = nil
        buildIndex()
        withAnimation(.snappy(duration: 0.3)) { searching = true }
        searchFocused = true
    }

    private func closeSearch() {
        searchFocused = false
        pinned.remove(level)
        tops[level] = nil
        withAnimation(.snappy(duration: 0.3)) {
            searching = false
            query = ""
            filters = []
        }
    }

    /// The bar at the bottom: the levels and a magnifying glass; searching, the field and the filters instead.
    @ViewBuilder
    var bottomBar: some View {
        if searching {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Notes, places, prayers, months", text: $query)
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                        if !query.isEmpty {
                            Button { query = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(.regularMaterial, in: Capsule())
                    Button(action: closeSearch) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close search")
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack(spacing: 10) {
                levelSwitch(glass: false)
                Button(action: openSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
            }
            .padding(.bottom, 4)
            .transition(.opacity)
        }
    }

    /// Months · Days · Prayers — for anyone who never finds the pinch. Plain buttons through the same `go` as the pinch,
    /// so the squares fly into their stacks the same way (the system segmented control changed the level un-animated).
    /// In the iOS 26 toolbar the system draws its glass; before that it sits on its own material capsule.
    func levelSwitch(glass: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Level.allCases) { l in
                Button { go(l) } label: {
                    Text(l.title)
                        .font(.system(size: 14, weight: level == l ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(level == l ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background {
                            if level == l {
                                Capsule().fill(Color.primary.opacity(glass ? 0.1 : 0))
                                    .background(Capsule().fill(Color(.systemBackground).opacity(glass ? 0 : 0.9)))
                                    .shadow(color: .black.opacity(glass ? 0 : 0.08), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "levelPill", in: pinch)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 250)
        .padding(glass ? 0 : 6)
        .background {
            if !glass { Capsule().fill(.regularMaterial) }
        }
    }

    // MARK: Search results, as a list (owner: "display the search results as a list")

    private var resultsList: some View {
        let results = filtering ? Array(visible.reversed()) : []
        return List {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(SearchFilter.allCases) { filter in
                            let on = filters.contains(filter)
                            Button {
                                withAnimation(.snappy(duration: 0.25)) {
                                    if on { filters.remove(filter) } else { filters.insert(filter) }
                                }
                            } label: {
                                Label(filter.rawValue, systemImage: filter.symbol)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 12).frame(height: 32)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .background(Capsule().fill(on ? AnyShapeStyle(Color.sage) : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !filtering {
                Text("Search your notes, masjids, places, prayers and months — Ramadan works too.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                Section(results.count == 1 ? "1 photo" : "\(results.count) photos") {
                    ForEach(results) { photo in
                        Button { openFromResults(photo) } label: { resultRow(photo) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private func resultRow(_ photo: MemoryPhoto) -> some View {
        HStack(spacing: 12) {
            MemoryThumb(key: photo.key)
                .frame(width: 52, height: 52)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.frames["result-" + photo.key] = $0 }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: prayerIcon(for: photo.name)).font(.system(size: 13))
                    Text(photo.name).font(.system(size: 16, weight: .semibold, design: .rounded))
                    if PrayerPhotoFavorites.shared.contains(photo.key) {
                        Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(.pink)
                    }
                }
                Text(Self.parse(photo.dayKey)?.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) ?? "")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                if let snippet = searchIndex[photo.key]?.snippet {
                    Text(snippet).font(.system(size: 13, design: .rounded)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func openFromResults(_ photo: MemoryPhoto) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        openDeck(photo, from: "result-" + photo.key)
    }

    // MARK: On this day (decision memories-finding C)

    /// Earlier years' photos from today's date, the newest year first.
    private var onThisDay: [[MemoryPhoto]] {
        let today = String(Self.dayKeyFormatter.string(from: Date()).dropFirst(5))
        let year = Calendar.current.component(.year, from: Date())
        let matches = photos.filter { $0.dayKey.dropFirst(5) == today && (Int($0.dayKey.prefix(4)) ?? year) < year }
        return Dictionary(grouping: matches, by: \.dayKey).sorted { $0.key > $1.key }.map(\.value)
    }

    private func onThisDayCard(_ dayPhotos: [MemoryPhoto]) -> some View {
        let dayKey = dayPhotos.first?.dayKey ?? ""
        let years = Calendar.current.component(.year, from: Date()) - (Int(dayKey.prefix(4)) ?? 0)
        return Button {
            if let newest = dayPhotos.last { openDeck(newest, from: "otd-" + dayKey) }
        } label: {
            HStack(spacing: 14) {
                stack(dayPhotos, side: 52, corner: 13)
                    .frame(width: 66, height: 66)
                    .onGeometryChange(for: CGRect.self) { proxy in
                        let f = proxy.frame(in: .global)
                        return CGRect(x: f.midX - 26, y: f.midY - 26, width: 52, height: 52)
                    } action: { frames.frames["otd-" + dayKey] = $0 }
                VStack(alignment: .leading, spacing: 2) {
                    Text("On this day").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("\(years == 1 ? "1 year" : "\(years) years") ago · "
                         + (Self.parse(dayKey)?.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()) ?? ""))
                        .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

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

    /// Days with at least one photo, oldest first, grouped by month (newest at the bottom, like Photos) — worked out
    /// once per change of what's shown (it was regrouped every time a level read it, several times a redraw).
    private var months: [Month] {
        let shown = visible
        let signature = "\(shown.count)|\(shown.first?.key ?? "")|\(shown.last?.key ?? "")|\(shown.reduce(0) { $0 &+ $1.key.hashValue })"
        if let cached = frames.months, cached.signature == signature { return cached.value }
        let value = Self.group(shown)
        frames.months = (signature, value)
        return value
    }

    private static func group(_ visible: [MemoryPhoto]) -> [Month] {
        let byDay = Dictionary(grouping: visible, by: \.dayKey)
        let days = byDay.keys.sorted(by: <).map { ($0, byDay[$0] ?? []) }
        let byMonth = Dictionary(grouping: days, by: { String($0.0.prefix(7)) })
        return byMonth.keys.sorted(by: <).map { month in
            let monthDays = (byMonth[month] ?? []).sorted { $0.0 < $1.0 }
            return (month, Self.monthTitle(month), monthDays, monthDays.flatMap(\.1))
        }
    }

    var body: some View {
        Group {
            // One scroll view per level, swapped whole: a shared one scrolled under the change and the squares never
            // flew into their stacks.
            Group {
                if photos.isEmpty {
                    ScrollView {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 34, weight: .light))
                            Text("No photos yet").font(.headline)
                            Text("After you mark a prayer, take a photo from the pill; it shows up here.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 140).padding(.horizontal, 40)
                    }
                } else if searching {
                    resultsList
                } else {
                    switch level {
                    case .months: levelScroll(.months) { monthStacks }
                    case .days: levelScroll(.days) { dayStacks }
                    case .prayers: levelScroll(.prayers) { prayerStrips }
                    }
                }
            }
            // The bottom bar: on iOS 26+ the system's bottom toolbar (Liquid Glass) — the level switch and a search
            // button, or, searching, the field and a close button. The system search controller (.searchable) was
            // dropped here: pushed onto the app's stack it drew a second, open search bar under the toolbar.
            .toolbar {
                if #available(iOS 26.0, *), hasPhotos {
                    if searching {
                        ToolbarItem(placement: .bottomBar) { searchField }
                        ToolbarSpacer(.fixed, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            Button(action: closeSearch) { Image(systemName: "xmark") }
                                .accessibilityLabel("Close search")
                        }
                    } else {
                        ToolbarItem(placement: .bottomBar) { levelSwitch(glass: true) }
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                        ToolbarItem(placement: .bottomBar) {
                            Button(action: openSearch) { Image(systemName: "magnifyingglass") }
                                .accessibilityLabel("Search")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Before iOS 26 (no Liquid Glass): the page's own bar.
                if !Self.glassBar, hasPhotos { bottomBar }
            }
            .simultaneousGesture(
                MagnifyGesture().onEnded { value in
                    if value.magnification < 0.8, let up = Level(rawValue: level.rawValue - 1) { go(up) }
                    if value.magnification > 1.25, let down = Level(rawValue: level.rawValue + 1) { go(down) }
                }
            )
            .onChange(of: searching) { _, on in
                if on {
                    pinned.remove(level)
                    tops[level] = nil
                    buildIndex()
                } else {
                    query = ""
                    filters = []
                }
            }
            .onChange(of: placeNamesLearned) { _, _ in if searching { buildIndex() } }
            .sensoryFeedback(.selection, trigger: level)
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Photo settings")
                }
            }
            .sheet(isPresented: $showSettings) { MemoriesSettings() }
        }
        // The pile in its own clear layer over everything, presented without a slide (like a prayer photo from the hold
        // editor): the page's bars stay as they are underneath. Hiding them for the pile and bringing them back left a
        // second, ghost bottom bar with an empty search field (owner's screenshot) once Memories was pushed.
        .fullScreenCover(item: $deckStart) { start in
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.12))
                        .ignoresSafeArea()
                        .opacity(deckShown ? 1 : 0)
                    // Its own stack, so Share pushes its page inside the layer.
                    NavigationStack {
                        MemoriesDeck(photos: visible, start: start, shown: deckShown, hideTop: flight != nil,
                                     folded: folding, onTopFrame: deckTopMoved, onClose: closeDeck)
                            .containerBackground(.clear, for: .navigation)
                    }
                    if let flight {
                        let base = flight.rect.width > 0 ? Self.cardWidth : 1
                        PrayerPhotoFace(back: flight.images.back, front: flight.images.front, width: base)
                            .shadow(color: .black.opacity(0.18 * flight.opacity), radius: 14, y: 8)
                            .scaleEffect(flight.rect.width / base)
                            .position(x: flight.rect.midX, y: flight.rect.midY)
                            .opacity(flight.opacity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                }
                .presentationBackground(.clear)
        }
        .task(id: PrayerPhotoRevision.shared.value) { photos = PrayerPhotos.all() }
    }

    private func levelScroll<Content: View>(_ l: Level, @ViewBuilder content: () -> Content) -> some View {
        ScrollView { content() }
            .scrollPosition(id: Binding(get: { tops[l] }, set: { tops[l] = $0 }), anchor: .top)
            .defaultScrollAnchor(pinned.contains(l) ? .top : .bottom)
            // Search on or off starts the list afresh at the bottom (kept, it was left scrolled to the top).
            .id("\(l.rawValue)-\(filtering)")
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

    /// The pile's card width (`MemoriesDeck` uses the same).
    static var cardWidth: CGFloat { min(UIScreen.main.bounds.width - 72, 360) }

    /// The photo leaves its square: the pile mounts with its top card hidden, and once the pile has laid out the photo
    /// flies onto it while the page frosts over.
    private func openDeck(_ photo: MemoryPhoto, from source: String) {
        triggerSomeVibration(type: .light)
        let from = frames.frames[source]
        Task {
            let images = await PrayerPhotos.load(photo.key)
            frames.opening = true
            flight = Flight(key: photo.key, rect: from ?? .zero, images: images, opacity: from == nil ? 0 : 1)
            deckShown = false
            folding = false
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { deckStart = photo }
        }
    }

    /// The pile reports its top card. While opening, every report (re)aims the photo at it — the pile settles over a
    /// frame or two, and its first report is empty (aimed at that, the photo flew into nothing).
    private func deckTopMoved(_ rect: CGRect) {
        guard rect.width > 1 else { return }
        frames.deckTop = rect
        guard frames.opening, flight != nil else { return }
        let token = UUID()
        frames.flightToken = token
        if flight?.rect == .zero { flight?.rect = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1) }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            flight?.rect = rect
            flight?.opacity = 1
            deckShown = true
        } completion: {
            guard frames.flightToken == token else { return }
            frames.opening = false
            flight = nil
        }
    }

    /// The photo on top flies back into its square (its day's pile on Days, its own square on Prayers) — or, when that
    /// isn't on screen, shrinks and fades where it is — while the frost lifts.
    private func closeDeck(_ key: String, _ dayKey: String, _ scale: CGFloat) {
        triggerSomeVibration(type: .light)
        var quiet = Transaction()
        quiet.disablesAnimations = true
        guard let top = frames.deckTop else { withTransaction(quiet) { deckStart = nil }; return }
        let screen = UIScreen.main.bounds
        let onScreen: (CGRect) -> Bool = { $0.minY > 90 && $0.maxY < screen.height - 70 && $0.minX >= 0 && $0.maxX <= screen.width }
        let target = (searching ? ["result-" + key] : ["otd-" + dayKey, level == .prayers ? key : dayKey])
            .compactMap { frames.frames[$0] }.first(where: onScreen)
        // The pile gathers into its top card at once, so only that photo is left to fly.
        withAnimation(.easeOut(duration: 0.18)) { folding = true }
        // Where the top card is now, shrunk as the drag left it.
        let start = CGRect(x: top.midX - top.width * scale / 2, y: top.midY - top.height * scale / 2,
                           width: top.width * scale, height: top.height * scale)
        Task {
            let images = await PrayerPhotos.load(key)
            flight = Flight(key: key, rect: start, images: images)
            // A turn later, so the flight is drawn where it starts (set and moved in one turn, it never showed moving).
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
                if let target {
                    flight?.rect = target
                } else {
                    flight?.rect = start.insetBy(dx: start.width * 0.12, dy: start.height * 0.12)
                    flight?.opacity = 0
                }
                deckShown = false
            } completion: {
                withTransaction(quiet) {
                    deckStart = nil
                    flight = nil
                }
            }
        }
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
            // Under today's month, where the page opens: earlier years' photos from today's date.
            if !filtering {
                ForEach(onThisDay, id: \.first?.key) { dayPhotos in
                    onThisDayCard(dayPhotos).padding(.top, 6)
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
                        .onGeometryChange(for: CGRect.self) { proxy in
                            let f = proxy.frame(in: .global)
                            return CGRect(x: f.midX - 19, y: f.midY - 19, width: 38, height: 38)
                        } action: { frames.frames[dayKey] = $0 }
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
                    // Small piles get a small shadow (dozens of 8 pt blurs were the costliest thing to draw mid-switch).
                    .shadow(color: .black.opacity(side < 60 ? 0.12 : 0.16), radius: side < 60 ? 2 : 8, y: side < 60 ? 1 : 4)
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
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.frames[photo.key] = $0 }
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

    /// One formatter for every day key (a new one per call — hundreds per level switch — was slow).
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static var parsed: [String: Date] = [:]

    static func parse(_ dayKey: String) -> Date? {
        if let hit = parsed[dayKey] { return hit }
        let date = dayKeyFormatter.date(from: dayKey)
        if let date { parsed[dayKey] = date }
        return date
    }

    private static var monthTitles: [String: String] = [:]

    static func monthTitle(_ month: String) -> String {
        if let hit = monthTitles[month] { return hit }
        let title = parse(month + "-01").map { $0.formatted(.dateTime.month(.wide).year()) } ?? month
        monthTitles[month] = title
        return title
    }
}

/// A photo's back picture as a rounded square that fills whatever frame it's given (so a pinch can grow it into its
/// month's stack and back).
private struct MemoryThumb: View {
    let key: String
    var side: Int = 180
    var corner: CGFloat = 12
    @State private var image: UIImage?

    init(key: String, side: Int = 180, corner: CGFloat = 12) {
        self.key = key
        self.side = side
        self.corner = corner
        _image = State(initialValue: PrayerPhotos.cachedThumbnail(key, side: side))
    }

    var body: some View {
        Color.primary.opacity(0.08)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .task(id: "\(key)-\(PrayerPhotoMain.shared.isSelfie(key))") {
                let fresh = await PrayerPhotos.thumbnail(key, side: side)
                if fresh !== image { image = fresh }
            }
            .accessibilityLabel(PrayerPhotos.caption(key))
            .accessibilityAddTraits(.isButton)
    }
}

// MARK: - The pile

/// One day's loose pile at a time (owner: "make it one stack for a day"): its photos in order, older under, newer on
/// top. `index` is the photo on top, centred and nearly straight; the ones already seen lie under it, each at its own
/// random nudge and tilt. Swipe left: the day's next one comes in from the right; swipe right: the top one goes back off
/// to the right. Past the day's last (or first) photo the whole pile follows the finger and the next (previous) day's
/// pile slides in from that side — landing on its first photo going forward, its last going back. The day's date sits
/// at the top and slides only when the day changes; the prayer's name, its line and its note slide sideways with every
/// photo. Just the photos (owner: "no text or badges in the photo at time of viewing"); Share opens the share page.
/// Presented full screen with the system's zoom from the day or square it was opened from.
struct MemoriesDeck: View {
    let photos: [MemoryPhoto]
    let start: MemoryPhoto
    /// The page shows the pile's other parts once the photo is on its way (and hides them as it flies back).
    let shown: Bool
    /// The top card is the one in flight.
    let hideTop: Bool
    /// Where the top card is, for the photo's flight.
    let onTopFrame: (CGRect) -> Void
    /// Close with this photo (and its day) on top.
    /// Close with this photo (and its day) on top, and how far the pile is shrunk right now (it flies home from there).
    let onClose: (_ key: String, _ dayKey: String, _ scale: CGFloat) -> Void
    /// Closing: the cards under the top one gather into it and fade, so only the top photo flies home (no ghost pile).
    let folded: Bool
    @Environment(\.modelContext) private var context
    @AppStorage(PrayerPhotos.showPlaceKey) private var showPlace = false
    /// Which way the last move went: back in time or forward — everything that changes slides in from that side.
    @State private var wentBack = false
    /// Days sit side by side like the strip's (owner: "respect previous days and next days so that the stack moves to the
    /// left or the stack moves to the right"): the previous day's pile waits off the left edge, the next day's off the
    /// right, and a day change moves all three — `paging` goes to −width going forward, +width going back — then the new
    /// day becomes the current one in place. `incoming` stands in on that side for a jump from the strip.
    @State private var paging: CGFloat = 0
    @State private var incoming: Incoming?
    /// The photo a day change is landing on (the caption and the strip already show it).
    @State private var pendingTop: Int?
    @State private var pagingToken = UUID()

    struct Incoming { var range: ClosedRange<Int>; var top: Int; var fromRight: Bool }
    /// "Prayed 1:12 PM · Masjid Al-Noor" for the top photo, and its score (the badge under it).
    /// Each photo's caption details, by key (`prepareInfo`).
    @State private var infos: [String: CaptionInfo] = [:]
    @State private var showingPlace = false
    @State private var editingNote = false
    @State private var noteDraft = ""
    @State private var index: Int
    @State private var drag: CGFloat = 0
    /// A drag down: the pile follows the finger and shrinks a little, then closes.
    @State private var down: CGFloat = 0
    /// The drag-to-close follows the finger anywhere (owner: as on the today page's photo).
    @State private var freeDrag: CGSize = .zero
    /// How far the pile has gathered into its top card: with the drag, and all the way while closing.
    private var fold: CGFloat { folded ? 1 : min(down / 220, 1) }
    private var dragScale: CGFloat { 1 - min(down / 1600, 0.2) }
    /// Which way this drag went, fixed by its first move.
    @State private var vertical: Bool?
    /// Where each card lies in the pile, picked at random the first time it's needed (owner: "just do random angles …
    /// feel more hand made"); not stored.
    @State private var lie: [String: Lie]
    @State private var sharing: String?
    /// The day centred in the strip at the bottom: follows the pile, and a drag on the strip moves the pile there once
    /// it comes to rest.
    @State private var stripDay: String?

    struct Lie { var dx: CGFloat; var dy: CGFloat; var tilt: Double }

    /// How many seen cards show under the top one.
    private static let pileDepth = 4

    init(photos: [MemoryPhoto], start: MemoryPhoto, shown: Bool, hideTop: Bool, folded: Bool,
         onTopFrame: @escaping (CGRect) -> Void,
         onClose: @escaping (_ key: String, _ dayKey: String, _ scale: CGFloat) -> Void) {
        self.folded = folded
        self.photos = photos
        self.start = start
        self.shown = shown
        self.hideTop = hideTop
        self.onTopFrame = onTopFrame
        self.onClose = onClose
        let first = photos.firstIndex(of: start) ?? 0
        _index = State(initialValue: first)
        _lie = State(initialValue: Self.lies(around: first, in: photos, keeping: [:]))
        _stripDay = State(initialValue: photos.indices.contains(first) ? photos[first].dayKey : nil)
    }

    /// The top photo's day, as indices into `photos`.
    private var day: ClosedRange<Int> { dayRange(of: index) }

    /// The photo the page shows as current: the one a day change is landing on, else the top one.
    private var shownIndex: Int { pendingTop ?? index }

    private func dayRange(of i: Int) -> ClosedRange<Int> {
        guard photos.indices.contains(i) else { return 0...0 }
        let key = photos[i].dayKey
        var lo = i, hi = i
        while lo > 0 && photos[lo - 1].dayKey == key { lo -= 1 }
        while hi < photos.count - 1 && photos[hi + 1].dayKey == key { hi += 1 }
        return lo...hi
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 72, 360)
            let current = photos.indices.contains(shownIndex) ? photos[shownIndex] : nil
            let range = day
            let shift = edgeShift(range)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    if let left = neighbour(range, right: false) {
                        restingPile(left.range, top: left.top, width: width, screen: geo.size.width)
                            .offset(x: -geo.size.width + shift + paging)
                    }
                    pile(range, width: width, screen: geo.size.width)
                        .offset(x: shift + paging)
                    if let right = neighbour(range, right: true) {
                        restingPile(right.range, top: right.top, width: width, screen: geo.size.width)
                            .offset(x: geo.size.width + shift + paging)
                    }
                }
                .frame(width: geo.size.width, height: width + 30)
                .contentShape(Rectangle())
                .offset(freeDrag)
                .scaleEffect(dragScale)
                .gesture(pileDrag(range))
                if let current { caption(current).padding(.top, 24).opacity(shown ? 1 : 0) }
                // Share and ✕ under it, the grey circles of a photo opened from the hold editor (owner). Always there,
                // never redrawn per photo: the share page makes the picture.
                HStack(spacing: 18) {
                    Button { if photos.indices.contains(index) { sharing = photos[index].key } } label: {
                        circleIcon("square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    let favorite = photos.indices.contains(shownIndex) && PrayerPhotoFavorites.shared.contains(photos[shownIndex].key)
                    Button {
                        guard photos.indices.contains(shownIndex) else { return }
                        triggerSomeVibration(type: .light)
                        PrayerPhotoFavorites.shared.toggle(photos[shownIndex].key)
                    } label: {
                        circleIcon(favorite ? "heart.fill" : "heart", tint: favorite ? .pink : .primary)
                    }
                    .accessibilityLabel(favorite ? "Remove from favorites" : "Favorite")
                    Button(action: close) { circleIcon("xmark") }
                        .accessibilityLabel("Close")
                }
                .buttonStyle(.plain)
                .opacity(down > 10 || !shown ? 0 : 1)
                .padding(.top, 22)
                Spacer(minLength: 0)
                prayerMarks
                    .opacity(shown ? 1 - min(max(down, 0) / 120, 1) : 0)
                    .padding(.bottom, 10)
                VStack(spacing: 8) {
                    // The strip is its own bar (owner: "put a separator for that new bottom bar"; the system Divider was too
                    // faint on the frosted page).
                    Rectangle().fill(Color.primary.opacity(0.22)).frame(height: 1)
                    MemoriesDayStrip(photos: photos, centred: $stripDay, onScrub: scrubTo, onRest: goToDay)
                }
                .opacity(shown ? 1 - min(max(down, 0) / 120, 1) : 0)
                .padding(.bottom, 6)
            }
            .frame(width: geo.size.width)
            // No tap-to-close on the frosted page: a missed tap on the note or a prayer symbol closed it (owner) —
            // ✕ or a drag down closes.
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $editingNote) {
            // The whole note, to read and edit (the pile shows three lines of it).
            NavigationStack {
                TextEditor(text: $noteDraft)
                    .font(.system(size: 17, design: .rounded))
                    .padding(.horizontal, 12)
                    .navigationTitle(photos.indices.contains(index) ? PrayerPhotos.caption(photos[index].key) : "Note")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingNote = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if photos.indices.contains(shownIndex) {
                                    PrayerPhotos.setNote(photos[shownIndex].key, noteDraft)
                                    infos[photos[shownIndex].key]?.note = PrayerPhotos.note(photos[shownIndex].key)
                                }
                                editingNote = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { prepareInfo(around: shownIndex) }
        .onChange(of: shownIndex) { _, i in prepareInfo(around: i) }
        .sheet(isPresented: $showingPlace) {
            if photos.indices.contains(shownIndex), let info = infos[photos[shownIndex].key], let spot = info.facts?.spot {
                PrayerPlaceMapSheet(caption: PrayerPhotos.caption(photos[shownIndex].key), place: info.place ?? "",
                                    spot: spot, score: info.score, atMasjid: info.facts?.masjid != nil)
            }
        }
        .navigationDestination(item: $sharing) { key in PrayerPhotoShareComposer(key: key) }
        .sensoryFeedback(.selection, trigger: shownIndex)
        .onChange(of: shownIndex) { _, i in
            // The strip follows the pile.
            guard photos.indices.contains(i), photos[i].dayKey != stripDay else { return }
            withAnimation(.snappy(duration: 0.35)) { stripDay = photos[i].dayKey }
        }
        .onAppear {
            PrayerPhotoViewing.shared.opened()
            pickLies()
        }
        .onDisappear { PrayerPhotoViewing.shared.closed() }
    }

    private func close() {
        guard photos.indices.contains(index) else { return }
        onClose(photos[index].key, photos[index].dayKey, dragScale)
    }

    /// The day waiting off one edge: the strip's jump if it's coming from that side, else the next day (on its first
    /// photo) or the previous day (on its last).
    private func neighbour(_ range: ClosedRange<Int>, right: Bool) -> Incoming? {
        if let incoming, incoming.fromRight == right { return incoming }
        if right, range.upperBound < photos.count - 1 {
            let next = dayRange(of: range.upperBound + 1)
            return Incoming(range: next, top: next.lowerBound, fromRight: true)
        }
        if !right, range.lowerBound > 0 {
            let previous = dayRange(of: range.lowerBound - 1)
            return Incoming(range: previous, top: previous.upperBound, fromRight: false)
        }
        return nil
    }

    /// Past the day's last (or first) photo, every pile follows the finger, the next (previous) day's coming in.
    private func edgeShift(_ range: ClosedRange<Int>) -> CGFloat {
        (index == range.upperBound && drag < 0) || (index == range.lowerBound && drag > 0) ? drag : 0
    }

    /// To another day: all the piles slide a page over, then that day is the current one, on `top`.
    private func page(to top: Int, fromRight: Bool, jump: Bool, response: Double = 0.42) {
        finishPaging()
        guard photos.indices.contains(top) else { return }
        let screen = UIScreen.main.bounds.width
        if jump { incoming = Incoming(range: dayRange(of: top), top: top, fromRight: fromRight) }
        lie = Self.lies(around: top, in: photos, keeping: lie)
        prepareInfo(around: top)
        let token = UUID()
        pagingToken = token
        moving(back: !fromRight) {
            withAnimation(.spring(response: response, dampingFraction: 0.9)) {
                pendingTop = top
                paging = fromRight ? -screen : screen
                drag = 0
            } completion: {
                guard pagingToken == token else { return }
                land(top)
            }
        }
    }

    /// The caption's slide takes its side from `wentBack` as the leaving name last drew it, so a flip of direction is
    /// drawn a turn before the move (in the same turn the old name left the wrong way: 7th → 6th, both from the left).
    private func moving(back: Bool, _ change: @escaping () -> Void) {
        guard wentBack != back else { change(); return }
        wentBack = back
        DispatchQueue.main.async(execute: change)
    }

    /// The day that slid in becomes the current one where it is (no movement, no fade).
    private func land(_ top: Int) {
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            index = top
            paging = 0
            incoming = nil
            pendingTop = nil
        }
        pickLies()
    }

    /// A day change still moving lands at once (a new swipe, or the strip moving on).
    private func finishPaging() {
        guard let top = pendingTop else { return }
        pagingToken = UUID()
        land(top)
    }

    /// The strip passing a day under the finger: that day's pile at once, if it has photos (owner: "the scrubber … isn't
    /// updating as we scroll"); days without photos are passed over until the strip comes to rest.
    private func scrubTo(_ dayKey: String) {
        guard photos.indices.contains(shownIndex), dayKey != photos[shownIndex].dayKey,
              let newest = photos.lastIndex(where: { $0.dayKey == dayKey }) else { return }
        page(to: newest, fromRight: dayKey > photos[shownIndex].dayKey, jump: true, response: 0.3)
    }

    /// The day's five prayers as their symbols, above the strip (owner: "so user can see visually which part of the day
    /// they are in as they swipe"): the one on top bright and a little bigger, the others with a photo dimmer, those
    /// without faint; a tap goes to that prayer's photo.
    private var prayerMarks: some View {
        let range = dayRange(of: shownIndex)
        return HStack(spacing: 26) {
            ForEach(["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"], id: \.self) { name in
                let i = range.first { photos[$0].name == name }
                let current = i == shownIndex
                Button {
                    guard let i, i != index, pendingTop == nil else { return }
                    moving(back: i < index) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { index = i; drag = 0 }
                        pickLies()
                    }
                } label: {
                    Image(systemName: prayerIcon(for: name))
                        .font(.system(size: 17, weight: current ? .semibold : .regular))
                        .foregroundStyle(current ? AnyShapeStyle(.primary) : i != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                        .scaleEffect(current ? 1.2 : 1)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(i == nil)
                .accessibilityLabel(name)
            }
        }
        .animation(.snappy(duration: 0.25), value: shownIndex)
    }

    /// A short slide with a fade, from the side the cards came from (owner: "more subtle … instead of going the whole
    /// width of the page").
    private func slide(_ distance: CGFloat) -> AnyTransition {
        let from = wentBack ? -distance : distance
        return .asymmetric(insertion: .offset(x: from).combined(with: .opacity),
                           removal: .offset(x: -from).combined(with: .opacity))
    }

    /// The strip came to rest on `dayKey`: that day's pile, on its newest photo; a day without photos sends the strip
    /// on to the nearest day that has some.
    private func goToDay(_ dayKey: String) {
        guard photos.indices.contains(shownIndex), dayKey != photos[shownIndex].dayKey else { return }
        if let newest = photos.lastIndex(where: { $0.dayKey == dayKey }) {
            page(to: newest, fromRight: dayKey > photos[shownIndex].dayKey, jump: true)
            return
        }
        let before = photos.last { $0.dayKey < dayKey }?.dayKey
        let after = photos.first { $0.dayKey > dayKey }?.dayKey
        let gap: (String?) -> Int = { other in
            guard let other, let a = MemoriesPage.parse(other), let b = MemoriesPage.parse(dayKey) else { return .max }
            return abs(Calendar.current.dateComponents([.day], from: a, to: b).day ?? .max)
        }
        if let nearest = gap(before) <= gap(after) ? before ?? after : after ?? before {
            withAnimation(.snappy(duration: 0.35)) { stripDay = nearest }
            goToDay(nearest)
        }
    }

    /// One day's cards: the seen ones under, the top one, and the day's next one waiting off to the right. Past the
    /// day's edge the whole pile follows the finger (a little only, at the very first and last photo).
    private func pile(_ range: ClosedRange<Int>, width: CGFloat, screen: CGFloat) -> some View {
        let atStart = index == range.lowerBound, atEnd = index == range.upperBound
        let shown = Array(max(range.lowerBound, index - Self.pileDepth)...min(index + 1, range.upperBound))
        return ZStack {
            ForEach(shown, id: \.self) { i in
                card(i, width: width, screen: screen, atStart: atStart, atEnd: atEnd)
            }
        }
        .frame(width: screen, height: width + 30)
    }

    /// A neighbouring day's pile as it will be once it's the current one: `top` straight on top, the earlier ones under
    /// it at their lies — drawn the same, so landing on it changes nothing on screen.
    private func restingPile(_ range: ClosedRange<Int>, top: Int, width: CGFloat, screen: CGFloat) -> some View {
        let cards = Array(max(range.lowerBound, top - Self.pileDepth)...top)
        return ZStack {
            ForEach(cards, id: \.self) { i in
                let l = lie[photos[i].key] ?? Lie(dx: 0, dy: 0, tilt: 0)
                MemoryCard(key: photos[i].key, width: width)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                    .rotationEffect(.degrees(i == top ? 0 : l.tilt))
                    .offset(x: i == top ? 0 : l.dx, y: i == top ? 0 : l.dy)
                    .zIndex(Double(i))
            }
        }
        .frame(width: screen, height: width + 30)
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(false)
    }

    /// The prayer's name, its line and its note — they slide sideways with every photo.
    private func caption(_ current: MemoryPhoto) -> some View {
        // Its own photo's details, worked out before it shows (`prepareInfo`): the whole caption is one view that moves
        // as one — filled in after it slid in, its lines changed separately and seemed to move at their own speeds.
        let info = infos[current.key] ?? CaptionInfo()
        return ZStack {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: prayerIcon(for: current.name)).font(.system(size: 17))
                    Text(current.name).font(.system(size: 22, weight: .medium, design: .rounded))
                }
                // When (and where), then the score as a small ring in its grade's colour — each a line, always there.
                Text(info.prayed ?? " ")
                    .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Group {
                    if let place = info.place {
                        // A tap shows it on a map (owner).
                        Button { if info.facts?.spot != nil { showingPlace = true } } label: {
                            HStack(spacing: 4) {
                                Label(place, systemImage: "mappin.and.ellipse")
                                if info.facts?.spot != nil {
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(" ")
                    }
                }
                .font(.system(size: 13, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 36)
                Group {
                    if let score = info.score {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle().stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                                Circle().trim(from: 0, to: max(score, 0.02))
                                    .stroke(PrayerScoring.color(for: score), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Text("\(Int((score * 100).rounded()))")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                            }
                            .frame(width: 24, height: 24)
                            Text(PrayerScoring.grade(for: score).rawValue)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 26)
                // Three lines' room whether there's a note or not, so nothing on the page moves from photo to photo
                // (owner's note: a long one pushed the pile and the buttons, which clicked up and down on each swipe).
                Button {
                    noteDraft = info.note ?? ""
                    editingNote = true
                } label: {
                    Group {
                        if let note = info.note {
                            Text(note)
                                .font(.system(size: 14, design: .rounded)).italic()
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .truncationMode(.tail)
                        } else {
                            Label("Add a note", systemImage: "square.and.pencil")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .frame(height: 58, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 36)
                .padding(.top, 6)
            }
            // Follows the finger while a photo is dragged, then the next one's slides in as it lands.
            .offset(x: max(-90, min(90, drag * 0.35)))
            .opacity(1 - min(abs(drag) / 320, 0.6))
            .id(current.key)
            .transition(slide(36))
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .opacity(1 - min(max(down, 0) / 120, 1))
    }

    struct CaptionInfo {
        var prayed: String?
        var place: String?
        var score: Double?
        var note: String?
        var facts: PrayerPhotos.Facts?
    }

    /// The details of every photo in the day of `i` and the days either side, worked out now (the database and the
    /// notes are on the phone); a place's name the phone hasn't learnt yet is looked up once and filled in after.
    private func prepareInfo(around i: Int) {
        guard photos.indices.contains(i) else { return }
        let r = dayRange(of: i)
        var lo = r.lowerBound, hi = r.upperBound
        if lo > 0 { lo = dayRange(of: lo - 1).lowerBound }
        if hi < photos.count - 1 { hi = dayRange(of: hi + 1).upperBound }
        var lookups: [(String, PrayerPhotos.Facts)] = []
        for index in lo...hi {
            let key = photos[index].key
            guard infos[key] == nil else { continue }
            var found = PrayerPhotos.facts(for: key, in: context)
            #if DEBUG
            // `-demoPlace`: a marked time, a score and a spot in Manhattan for the stand-in photos (no prayer rows).
            if found == nil, ProcessInfo.processInfo.arguments.contains("-demoPlace") {
                found = PrayerPhotos.Facts(markedAt: Date(), score: 0.86, masjid: nil,
                                           spot: CLLocationCoordinate2D(latitude: 40.7536, longitude: -73.9832))
            }
            #endif
            var info = CaptionInfo(note: PrayerPhotos.note(key), facts: found)
            if let facts = found {
                info.prayed = facts.markedAt.map { "Prayed \($0.formatted(date: .omitted, time: .shortened))" }
                info.score = facts.score
                info.place = facts.masjid ?? facts.spot.flatMap { PrayerPlaceNames.name($0) }
                if info.place == nil, facts.spot != nil { lookups.append((key, facts)) }
            }
            infos[key] = info
        }
        for (key, facts) in lookups {
            Task {
                if let city = await PrayerPhotos.placeText(facts, cityOnly: true) { infos[key]?.place = city }
            }
        }
    }

    private func circleIcon(_ symbol: String, tint: Color = .primary) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 50, height: 50)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    @ViewBuilder
    private func card(_ i: Int, width: CGFloat, screen: CGFloat, atStart: Bool, atEnd: Bool) -> some View {
        let key = photos[i].key
        let l = lie[key] ?? Lie(dx: 0, dy: 0, tilt: 0)
        let (x, y, angle): (CGFloat, CGFloat, Double) = {
            if i > index {
                // The day's next one, waiting off to the right; a swipe left pulls it in.
                let x = screen + (atEnd ? 0 : min(drag, 0))
                return (x, 0, Double(x) / 40)
            } else if i == index {
                // On top: centred and straight (so the photo flies onto it and off it without a twist); a swipe right
                // takes it back off to the right (at the day's first photo the whole pile moves instead).
                let x = atStart ? 0 : max(drag, 0)
                return (x, 0, Double(x) / 40)
            } else {
                return (l.dx * (1 - fold), l.dy * (1 - fold), l.tilt * (1 - fold))
            }
        }()
        MemoryCard(key: key, width: width)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                if i == index { onTopFrame(rect) }
            }
            .opacity(i == index ? (hideTop ? 0 : 1) : (shown ? 1 - fold : 0))
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

    private func pileDrag(_ range: ClosedRange<Int>) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if vertical == nil {
                    vertical = abs(value.translation.height) > abs(value.translation.width)
                }
                if vertical == true {
                    freeDrag = value.translation
                    down = hypot(value.translation.width, value.translation.height)
                    return
                }
                finishPaging()
                let t = value.translation.width
                // At the very first and last photo the pile gives a little and comes back.
                if t < 0, index >= photos.count - 1 { drag = t / 6 } else if t > 0, index == 0 { drag = t / 6 } else { drag = t }
            }
            .onEnded { value in
                defer { vertical = nil }
                if vertical == true {
                    let flung = hypot(value.predictedEndTranslation.width, value.predictedEndTranslation.height)
                    if down > 120 || flung > 320 {
                        // Home from right where it is (the page flies it; the pile stays put and gathers).
                        close()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { down = 0; freeDrag = .zero }
                    }
                    return
                }
                let far = value.translation.width, flung = value.predictedEndTranslation.width
                let settle = Animation.spring(response: 0.42, dampingFraction: 0.82)
                if (far < -90 || flung < -240), index < photos.count - 1 {
                    if index == range.upperBound {
                        // Past the day's last: this day goes off to the left, the next comes in from the right.
                        page(to: index + 1, fromRight: true, jump: false)
                    } else {
                        // The day's next one lands on top.
                        moving(back: false) {
                            withAnimation(settle) { index += 1; drag = 0 }
                            pickLies()
                        }
                    }
                } else if (far > 90 || flung > 240), index > 0 {
                    if index == range.lowerBound {
                        // Past the day's first: this day goes off to the right, the previous comes in from the left.
                        page(to: index - 1, fromRight: false, jump: false)
                    } else {
                        // The top one goes back off to the right.
                        moving(back: true) {
                            withAnimation(settle) { index -= 1; drag = 0 }
                            pickLies()
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { drag = 0 }
                }
            }
    }

    /// A random lie for each card near the top — and for the neighbouring days' piles waiting off the edges, so a day
    /// sliding in already lies the way it will once it's the current one.
    private func pickLies() {
        var all = Self.lies(around: index, in: photos, keeping: lie)
        let r = day
        if r.lowerBound > 0 { all = Self.lies(around: r.lowerBound - 1, in: photos, keeping: all) }
        if r.upperBound < photos.count - 1 { all = Self.lies(around: r.upperBound + 1, in: photos, keeping: all) }
        lie = all
    }

    private static func lies(around index: Int, in photos: [MemoryPhoto], keeping: [String: Lie]) -> [String: Lie] {
        var lie = keeping
        let around = max(index - pileDepth - 1, 0)..<min(index + 3, photos.count)
        for i in around where lie[photos[i].key] == nil {
            lie[photos[i].key] = Lie(dx: .random(in: -22...22), dy: .random(in: -14...14), tilt: .random(in: -9...9))
        }
        return lie
    }
}

/// The days along the bottom of the pile (owner, decision memories-day-strip A): every day from the first photo to
/// today, the number with its weekday under it; the centred one is the pile's, full and a little bigger, the others
/// shrink and fade with their distance from the centre (`visualEffect` in the scroll view's space); days without photos
/// are faint and the pile skips them. Each month's name and its photo count sit above its 1st, and the month in view
/// stays pinned at the left edge until the next month's name pushes it out. Lazy: only numbers, only what's on screen.
struct MemoriesDayStrip: View {
    let photos: [MemoryPhoto]
    @Binding var centred: String?
    /// A day passing the centre under the finger.
    let onScrub: (String) -> Void
    let onRest: (String) -> Void
    /// Built before the first layout, so the strip opens on the pile's day (built later, `scrollPosition` had nothing to
    /// find and it opened elsewhere).
    @State private var days: [String]
    @State private var photoDays: Set<String>
    @State private var monthCounts: [String: Int]

    init(photos: [MemoryPhoto], centred: Binding<String?>, onScrub: @escaping (String) -> Void,
         onRest: @escaping (String) -> Void) {
        self.onScrub = onScrub
        self.photos = photos
        self._centred = centred
        self.onRest = onRest
        let model = Self.model(photos)
        _days = State(initialValue: model.days)
        _photoDays = State(initialValue: model.photoDays)
        _monthCounts = State(initialValue: model.monthCounts)
    }
    /// The earliest day in view (its month is the pinned one), and where each month's 1st sits in the view.
    @State private var leftmost: String?
    @State private var firstX: [String: CGFloat] = [:]
    @State private var pinnedWidth: CGFloat = 80
    @State private var phase: ScrollPhase = .idle
    @State private var tick = 0

    private static let cell: CGFloat = 50
    private static let labelHeight: CGFloat = 34

    /// Where the strip is scrolled, set by us from the day's place in the list (the id-based position didn't move a
    /// short strip — three days on the owner's phone — so the pile's day and the strip's drifted apart).
    @State private var position = ScrollPosition()
    @State private var margin: CGFloat = 0
    /// The day under the centre now, from the scroll offset.
    @State private var centreIndex = 0

    private func scroll(to day: String?, animated: Bool) {
        guard let day, let i = days.firstIndex(of: day), margin > 0 else { return }
        // ScrollPosition's x counts from the content's start, margins excluded (the content offset reads −margin there).
        let x = CGFloat(i) * Self.cell
        if animated {
            withAnimation(.snappy(duration: 0.35)) { position.scrollTo(x: x) }
        } else {
            position.scrollTo(x: x)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let margin = (geo.size.width - Self.cell) / 2
            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            dayCell(day).id(day)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, margin, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition($position)
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { ids in leftmost = ids.min() }
                // The day under the centre as the finger moves, from the offset itself (the position binding only
                // caught up once the strip stopped).
                .onScrollGeometryChange(for: Int.self) { geo in
                    Int(((geo.contentOffset.x + geo.contentInsets.leading) / Self.cell).rounded())
                } action: { _, i in
                    centreIndex = i
                    guard phase == .interacting || phase == .decelerating, days.indices.contains(i) else { return }
                    tick += 1
                    onScrub(days[i])
                }
                .onScrollPhaseChange { _, new in
                    phase = new
                    if new == .idle, days.indices.contains(centreIndex) { onRest(days[centreIndex]) }
                }
                pinnedMonth
            }
            .coordinateSpace(name: "dayStrip")
            // The strip's real width (at its first appearance the reader still read 0, and nothing scrolled), then
            // straight onto the pile's day.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                let first = self.margin <= 0
                self.margin = (width - Self.cell) / 2
                if first { scroll(to: centred, animated: false) }
            }
        }
        // The pile moved to another day: the strip follows (not while a finger is on it).
        .onChange(of: centred) { _, day in
            guard phase != .interacting, phase != .decelerating else { return }
            scroll(to: day, animated: true)
        }
        .frame(height: Self.labelHeight + 50)
        .sensoryFeedback(.selection, trigger: tick)

    }

    private func dayCell(_ day: String) -> some View {
        let date = MemoriesPage.parse(day)
        let has = photoDays.contains(day)
        return VStack(spacing: 2) {
            Text(date.map { "\(Calendar.current.component(.day, from: $0))" } ?? "")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(date.map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? "")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .opacity(has ? 1 : 0.3)
        .visualEffect { content, proxy in
            let frame = proxy.frame(in: .scrollView(axis: .horizontal))
            let width = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? 0
            let distance = min(abs(frame.midX - width / 2) / 110, 1)
            return content
                .scaleEffect(1.2 - 0.35 * distance)
                .opacity(1 - 0.6 * distance)
        }
        .frame(width: Self.cell, height: 50)
        .padding(.top, Self.labelHeight)
        .overlay(alignment: .topLeading) {
            // The month's name over its 1st — unless it's the month pinned at the left edge.
            if day.hasSuffix("-01") {
                let month = String(day.prefix(7))
                monthLabel(month).fixedSize().padding(.leading, 8)
                    .opacity(month == pinnedMonthKey ? 0 : 1)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named("dayStrip")).minX
        } action: { x in
            if day.hasSuffix("-01") { firstX[String(day.prefix(7))] = x }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard has else { return }
            withAnimation(.snappy(duration: 0.35)) { centred = day }
            onRest(day)
        }
    }

    private func monthLabel(_ month: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(MemoriesPage.parse(month + "-01").map { $0.formatted(.dateTime.month(.wide).year()) } ?? month)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            let n = monthCounts[month] ?? 0
            Text(n == 1 ? "1 photo" : "\(n) photos")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var pinnedMonthKey: String? { leftmost.map { String($0.prefix(7)) } }

    /// The month of the earliest day in view, at the left edge; the next month's 1st pushes it out as it arrives.
    @ViewBuilder
    private var pinnedMonth: some View {
        if let month = pinnedMonthKey {
            let next = firstX.filter { $0.key > month }.min { $0.key < $1.key }?.value ?? .infinity
            let push = min(0, next + 8 - (16 + pinnedWidth + 14))
            #if DEBUG
            let _ = ProcessInfo.processInfo.arguments.contains("-logDayStrip") ? print("STRIPDBG \(month) next=\(next) push=\(push)") : ()
            #endif
            monthLabel(month)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pinnedWidth = $0 }
                .padding(.leading, 16)
                .offset(x: push)
                .allowsHitTesting(false)
        }
    }

    /// Every day from the first photo to today, the days with photos, and each month's photo count.
    private static func model(_ photos: [MemoryPhoto]) -> (days: [String], photoDays: Set<String>, monthCounts: [String: Int]) {
        let photoDays = Set(photos.map(\.dayKey))
        let monthCounts = Dictionary(grouping: photos, by: { String($0.dayKey.prefix(7)) }).mapValues(\.count)
        guard let firstKey = photos.first?.dayKey, let start = MemoriesPage.parse(firstKey) else { return ([], photoDays, monthCounts) }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())
        var list: [String] = []
        var d = Calendar.current.startOfDay(for: start)
        while d <= today {
            list.append(f.string(from: d))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        if let last = photos.last?.dayKey, last > (list.last ?? "") { list.append(last) }
        return (list, photoDays, monthCounts)
    }
}

/// One card in the pile: the photo as it is (rounded square, the other picture in the corner), no text on it.
private struct MemoryCard: View {
    let key: String
    let width: CGFloat
    @State private var images: (back: UIImage?, front: UIImage?)

    /// The last few photos decoded, so a pile drawn again (a neighbouring day becoming the current one) shows its
    /// pictures from the first frame.
    private final class Pair { let images: (back: UIImage?, front: UIImage?); init(_ i: (back: UIImage?, front: UIImage?)) { images = i } }
    private static let cache: NSCache<NSString, Pair> = { let c = NSCache<NSString, Pair>(); c.countLimit = 40; return c }()
    private static func cacheKey(_ key: String) -> NSString { "\(key)-\(PrayerPhotoMain.selfieIsMain(key))" as NSString }

    init(key: String, width: CGFloat) {
        self.key = key
        self.width = width
        _images = State(initialValue: Self.cache.object(forKey: Self.cacheKey(key))?.images ?? (nil, nil))
    }

    var body: some View {
        let selfie = PrayerPhotoMain.shared.isSelfie(key)
        PrayerPhotoFace(back: images.back, front: images.front, width: width)
            .task(id: key) {
                guard images.back == nil else { return }
                images = await PrayerPhotos.load(key)
                Self.cache.setObject(Pair(images), forKey: Self.cacheKey(key))
            }
            .onChange(of: selfie) { _, _ in
                withAnimation(.snappy(duration: 0.25)) { images = (images.front, images.back) }
                Self.cache.setObject(Pair(images), forKey: Self.cacheKey(key))
            }
    }
}

/// Share: the picture that will be sent, with what goes on it (owner: "shukr and prayer name and date always stay. but
/// give them option to add location, prayer score as progress ring, choose primary pic by tapping the image").
struct PrayerPhotoShareComposer: View {
    let key: String
    @Environment(\.modelContext) private var context
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)
    @State private var options: PrayerShareOptions

    init(key: String) {
        self.key = key
        _options = State(initialValue: PrayerShareOptions(key: key))
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 48, 420)
            ScrollView {
                VStack(spacing: 22) {
                    options.framed(images, width: width)
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
                    PrayerShareControls(options: options).padding(.horizontal, 24)
                }
                .padding(.top, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            PrayerShareButton(options: options).padding(.horizontal, 24).padding(.bottom, 8)
        }
        .navigationTitle("Share")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            images = await PrayerPhotos.load(key)
            await options.load(in: context)
        }
        .task(id: "\(options.signature)|\(images.back?.hash ?? 0)") { options.render(images) }
    }
}

/// Memories' own settings (owner: "put the settings for memories and photos inside this page").
struct MemoriesSettings: View {
    @AppStorage(PrayerPhotos.showPlaceKey) private var showPlace = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Show where puts the place on the photos you share, and on a photo opened from a prayer.")) {
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


/// Where a prayer was prayed, on a map (owner: "clicking on the location should open a sheet with a map … toggle for
/// satellite view … the same UI style as in the map that we have already"): the prayer's pin as the app map draws it
/// (its grade colour; a masjid or the hands), the app map's glass capsule — Standard ⇄ Satellite (the same remembered
/// setting) and back to the pin (green while it's centred); drag and zoom freely.
struct PrayerPlaceMapSheet: View {
    let caption: String
    let place: String
    let spot: CLLocationCoordinate2D
    let score: Double?
    let atMasjid: Bool
    @AppStorage(MapModes.satelliteKey) private var satellite = false
    @State private var camera: MapCameraPosition
    @State private var awayFromPin = false
    @Environment(\.dismiss) private var dismiss

    init(caption: String, place: String, spot: CLLocationCoordinate2D, score: Double?, atMasjid: Bool) {
        self.caption = caption
        self.place = place
        self.spot = spot
        self.score = score
        self.atMasjid = atMasjid
        _camera = State(initialValue: .region(Self.region(spot)))
    }

    private static func region(_ spot: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: spot, latitudinalMeters: 700, longitudinalMeters: 700)
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                Marker(place.isEmpty ? caption : place,
                       systemImage: atMasjid ? "building.columns.fill" : "hands.and.sparkles.fill",
                       coordinate: spot)
                    .tint(PrayerScoring.color(for: score))
                UserAnnotation()
            }
            .mapStyle(satellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic))
            .mapControls { MapScaleView() }
            .onMapCameraChange(frequency: .continuous) { context in
                let centre = CLLocation(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
                let metresAcross = context.region.span.latitudeDelta * 111_000
                awayFromPin = centre.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
                    > max(metresAcross * 0.15, 25)
            }
            .overlay(alignment: .topTrailing) {
                // The app map's capsule: map style, then back to the pin.
                VStack(spacing: 0) {
                    Button { satellite.toggle() } label: {
                        Image(systemName: MapModes.globeSymbol(longitude: spot.longitude)).mapControlIcon()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(satellite ? "Standard map" : "Satellite map")
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 0.5)
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(Self.region(spot)) }
                    } label: {
                        Image(systemName: awayFromPin ? "mappin" : "mappin.and.ellipse")
                            .mapControlIcon(tint: awayFromPin ? nil : .green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to the prayer")
                }
                .mapGlass(Capsule())
                .padding(10)
            }
            .navigationTitle(place.isEmpty ? caption : place)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(place.isEmpty ? caption : place).font(.headline).lineLimit(1)
                        if !place.isEmpty { Text(caption).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
