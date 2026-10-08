//
//  PrayerPhotos.swift
//  shukr
//
//  A photo for a prayer, after it's marked (owner, 2026-10-06: "pictures to each prayer. like a bereal kinda feature …
//  after you mark it prayed"; private, no rush window — any time in the prayer's window while it's marked; front and
//  back camera at once; "make the photo cute by clipping its shape to a rounded rectangle … like bereal and locket").
//  Taken from the post-salah pill's camera, or the prayer's hold editor; shown in the editor and on the end-of-day page
//  (decision prayer-photos-day A). Files on this iPhone only (Application Support/PrayerPhotos), never sent anywhere.
//

import SwiftUI
import SwiftData
import CoreLocation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Store

/// One prayer's photo: the back camera's, and the front camera's when both were taken. Keyed by the prayer day and the
/// prayer's name ("2026-10-06-Asr"; Jumu'ah is Dhuhr's row).
enum PrayerPhotos {
    static func key(dayKey: String, name: String) -> String {
        "\(dayKey)-\(name == "Jumu'ah" ? "Dhuhr" : name)"
    }

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("PrayerPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// HEIC since decision prayer-photo-storage A (about a third of the old JPEGs); a photo saved before keeps its .jpg.
    static func url(_ key: String, front: Bool) -> URL {
        let heic = file(key, front: front, "heic")
        if FileManager.default.fileExists(atPath: heic.path) { return heic }
        let jpg = file(key, front: front, "jpg")
        return FileManager.default.fileExists(atPath: jpg.path) ? jpg : heic
    }

    private static func file(_ key: String, front: Bool, _ ext: String) -> URL {
        directory.appendingPathComponent("\(key)-\(front ? "front" : "back").\(ext)")
    }

    /// The photo's key from a back picture's file name ("2026-10-06-Asr-back.heic" → "2026-10-06-Asr"), else nil.
    static func key(fromFile name: String) -> String? {
        for suffix in ["-back.heic", "-back.jpg"] where name.hasSuffix(suffix) { return String(name.dropLast(suffix.count)) }
        return nil
    }

    /// Where it was prayed: the masjid's name, else the spot's address (callers check Show where).
    @MainActor static func place(for key: String, in context: ModelContext) async -> String? {
        let dayKey = String(key.prefix(10)), name = String(key.dropFirst(11))
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.prayerDayKey == dayKey && $0.name == name }))) ?? []
        guard let row = rows.first(where: \.isCompleted) ?? rows.first else { return nil }
        if let masjid = row.mosqueName, !masjid.isEmpty { return masjid }
        guard let lat = row.latPrayedAt, let lon = row.longPrayedAt else { return nil }
        return await PrayerSpotAddress.lookUp(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    // MARK: Notes (owner: "after taking a photo let them write a small text of notes so we fit the journal vibe")

    private static func noteURL(_ key: String) -> URL { directory.appendingPathComponent("\(key)-note.txt") }

    static func note(_ key: String) -> String? {
        (try? String(contentsOf: noteURL(key), encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }
    }

    static func setNote(_ key: String, _ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: noteURL(key))
        } else {
            try? trimmed.write(to: noteURL(key), atomically: true, encoding: .utf8)
        }
    }

    // MARK: The prayer behind a photo

    struct Facts {
        var markedAt: Date?
        var score: Double?
        var masjid: String?
        var spot: CLLocationCoordinate2D?
    }

    /// When it was marked, its score, and where (the Journal's line under a photo, the share page).
    @MainActor static func facts(for key: String, in context: ModelContext) -> Facts? {
        let dayKey = String(key.prefix(10)), name = String(key.dropFirst(11))
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.prayerDayKey == dayKey }))) ?? []
        guard let row = rows.first(where: { $0.isCompleted && ($0.name == name || (name == "Dhuhr" && $0.name == "Jumu'ah")) })
        else { return nil }
        let spot = row.latPrayedAt.flatMap { lat in row.longPrayedAt.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
        return Facts(markedAt: row.timeAtComplete, score: row.numberScore,
                     masjid: (row.mosqueName ?? "").isEmpty ? nil : row.mosqueName, spot: spot)
    }

    /// The place as words: the masjid, else the spot's address — or just its city and state.
    static func placeText(_ facts: Facts, cityOnly: Bool) async -> String? {
        if cityOnly { return await facts.spot.asyncMap { await PrayerSpotAddress.city($0) } ?? nil }
        if let masjid = facts.masjid { return masjid }
        return await facts.spot.asyncMap { await PrayerSpotAddress.lookUp($0) } ?? nil
    }

    /// How many photos there are and the space they take (Memories' settings).
    static func usage() async -> (count: Int, bytes: Int64) {
        await Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return (Set(files.compactMap { key(fromFile: $0.lastPathComponent) }).count, bytes)
        }.value
    }

    #if DEBUG
    /// `-demoMemories`: stand-in photos for the last three weeks, some prayers each day (Memories in the simulator).
    static func seedDemo() async {
        if ProcessInfo.processInfo.arguments.contains("-demoOnThisDay") {
            // "On this day": a photo from a year ago today, and two years ago.
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            for years in [1, 2] {
                guard let day = Calendar.current.date(byAdding: .year, value: -years, to: Date()) else { continue }
                let key = PrayerPhotos.key(dayKey: f.string(from: day), name: years == 1 ? "Maghrib" : "Fajr")
                guard !has(key), let back = demoScene(top: .systemIndigo, bottom: .systemPink, symbol: "sparkles") else { continue }
                await save(key, back: back, front: nil)
            }
        }
        let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        let symbols = ["sunrise.fill", "sun.max.fill", "cloud.sun.fill", "sunset.fill", "moon.stars.fill"]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        for d in 0..<21 {
            guard let day = Calendar.current.date(byAdding: .day, value: -d, to: Date()) else { continue }
            for (i, name) in names.enumerated() where Int.random(in: 0..<10) < 6 {
                let key = PrayerPhotos.key(dayKey: f.string(from: day), name: name)
                guard !has(key) else { continue }
                let hue = Double.random(in: 0...1)
                let back = demoScene(top: UIColor(hue: hue, saturation: 0.55, brightness: 0.55, alpha: 1),
                                     bottom: UIColor(hue: fmod(hue + 0.12, 1), saturation: 0.6, brightness: 0.85, alpha: 1),
                                     symbol: symbols[i])
                let front = demoScene(top: UIColor(hue: 0.07, saturation: 0.45, brightness: 0.9, alpha: 1),
                                      bottom: UIColor(hue: 0.04, saturation: 0.5, brightness: 0.7, alpha: 1),
                                      symbol: "face.smiling")
                if let back { await save(key, back: back, front: front) }
            }
        }
    }

    private static func demoScene(top: UIColor, bottom: UIColor, symbol: String) -> Data? {
        let size = CGSize(width: 900, height: 900)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            UIImage(systemName: symbol)?.withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: 300, y: 260, width: 300, height: 300))
        }.jpegData(compressionQuality: 0.8)
    }

    /// `-heicSelfTest`: encode a stand-in picture the way `save` does, decode it the way Memories does, print the times.
    static func heicSelfTest() async {
        guard let sample = demoScene(top: .systemTeal, bottom: .systemOrange, symbol: "sun.max.fill") else { return }
        let start = Date()
        guard let file = await encoded(sample, maxPixels: 1200) else { print("HEICTEST encode failed"); return }
        print("HEICTEST encoded \(file.ext) \(file.data.count / 1024) KB in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        let t = Date()
        let decoded: Bool = await Task.detached {
            guard let src = CGImageSourceCreateWithData(file.data as CFData, nil) else { return false }
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 160]
            return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) != nil && UIImage(data: file.data) != nil
        }.value
        print("HEICTEST decoded=\(decoded) in \(Int(Date().timeIntervalSince(t) * 1000)) ms")
    }

    /// The most recently saved photo's key (`-demoPhotoViewer`).
    static var newestKey: String? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let backs = files.filter { key(fromFile: $0.lastPathComponent) != nil }
        let newest = backs.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        return newest.flatMap { key(fromFile: $0.lastPathComponent) }
    }
    #endif

    static func has(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(key, front: false).path)
    }

    /// Downscaled and written off the main thread; the views showing photos redraw after.
    static func save(_ key: String, back: Data, front: Data?) async {
        // The card shows the back picture at most ~1000 px across, the front inset ~350 (decision prayer-photo-storage A).
        let backFile = await encoded(back, maxPixels: 1200)
        let frontFile: (data: Data, ext: String)? = if let front { await encoded(front, maxPixels: 700) } else { nil }
        await Task.detached(priority: .userInitiated) {
            guard let backFile else { return }
            for isFront in [false, true] {
                for ext in ["heic", "jpg"] { try? FileManager.default.removeItem(at: file(key, front: isFront, ext)) }
            }
            try? backFile.data.write(to: file(key, front: false, backFile.ext), options: .atomic)
            if let frontFile { try? frontFile.data.write(to: file(key, front: true, frontFile.ext), options: .atomic) }
        }.value
        await PrayerPhotoRevision.shared.bump()
    }

    /// The photo of an unmarked prayer goes with its mark (owner: "if we unmark a prayer, we should also get rid of that
    /// image"); every unmark path calls this after it resets the row.
    static func discard(for row: PrayerModel) {
        let key = key(dayKey: row.dayKey, name: row.name)
        if has(key) { delete(key) }
    }

    /// A prayer row has a photo (its unmark prompts say it will be deleted).
    static func exists(for row: PrayerModel) -> Bool { has(key(dayKey: row.dayKey, name: row.name)) }

    static func delete(_ key: String) {
        Task { @MainActor in
            PrayerPhotoMain.shared.set(key, selfie: false)
            PrayerPhotoFavorites.shared.set(key, false)
        }
        setNote(key, nil)
        for isFront in [false, true] {
            for ext in ["heic", "jpg"] { try? FileManager.default.removeItem(at: file(key, front: isFront, ext)) }
        }
        Task { @MainActor in PrayerPhotoRevision.shared.bump() }
    }

    /// Decoded off the main thread, ready to draw: `back` is the main picture (the selfie when it was made the main one
    /// — `PrayerPhotoMain`), `front` the one in the corner.
    static func load(_ key: String) async -> (back: UIImage?, front: UIImage?) {
        await Task.detached(priority: .userInitiated) {
            func image(_ front: Bool) -> UIImage? {
                guard let data = try? Data(contentsOf: url(key, front: front)) else { return nil }
                return UIImage(data: data)?.preparingForDisplay()
            }
            let back = image(false), front = image(true)
            return PrayerPhotoMain.selfieIsMain(key) && front != nil ? (front, back) : (back, front)
        }.value
    }

    /// The main picture's file (the thumbnails').
    static func mainURL(_ key: String) -> URL {
        let front = url(key, front: true)
        return PrayerPhotoMain.selfieIsMain(key) && FileManager.default.fileExists(atPath: front.path) ? front : url(key, front: false)
    }

    /// The prayer's score (0…1) for the share card's ring; Jumu'ah counts as 1.
    @MainActor static func score(for key: String, in context: ModelContext) -> Double? {
        let dayKey = String(key.prefix(10)), name = String(key.dropFirst(11))
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.prayerDayKey == dayKey }))) ?? []
        let row = rows.first { $0.isCompleted && ($0.name == name || (name == "Dhuhr" && $0.name == "Jumu'ah")) }
        return row?.numberScore
    }

    /// The photo the right way up, its longest side at most `maxPixels`, as HEIC (a JPEG where HEIC can't be written).
    static func encoded(_ data: Data, maxPixels: Int) async -> (data: Data, ext: String)? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixels]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let image = UIImage(cgImage: cg)
            #if !targetEnvironment(simulator)
            // The simulator hangs decoding HEIC (every decode, never returning — a phone reads it in ~30 ms,
            // `-heicSelfTest`), so it keeps JPEG.
            if let heic = image.heicData() { return (heic, "heic") }
            #endif
            return image.jpegData(compressionQuality: 0.82).map { ($0, "jpg") }
        }.value
    }
}

/// A photo is open (the floating card): whatever it was opened from waits for it — the day page let go of its fifth
/// after 8 s and the card closed with it (owner: "the window seems to close itself abruptly").
@MainActor @Observable final class PrayerPhotoViewing {
    static let shared = PrayerPhotoViewing()
    private(set) var open = 0
    var isOpen: Bool { open > 0 }
    func opened() { open += 1 }
    func closed() { open = max(0, open - 1) }
}

/// Bumps when a photo is saved or removed, so every view showing one reloads it.
@MainActor @Observable final class PrayerPhotoRevision {
    static let shared = PrayerPhotoRevision()
    private(set) var value = 0
    /// Any photo saved at all (the day page's Memories link), re-read only when one is saved or removed.
    private(set) var hasPhotos = !PrayerPhotos.all().isEmpty
    func bump() { value += 1; hasPhotos = !PrayerPhotos.all().isEmpty }
}

/// What the camera is for: the prayer's key and its line ("Asr · 4:52 PM").
struct PrayerPhotoTarget: Identifiable {
    let key: String
    let title: String
    var id: String { key }

    /// Today's marked row of this prayer (the pill's name may be "Jumu'ah"), if it's still in its window.
    @MainActor static func forMarked(_ row: PrayerModel) -> PrayerPhotoTarget? {
        guard row.isCompleted else { return nil }
        let at = row.timeAtComplete ?? Date()
        return PrayerPhotoTarget(key: PrayerPhotos.key(dayKey: row.dayKey, name: row.name),
                                 title: "\(row.displayName) · \(shortTimePM(at))")
    }
}

// MARK: - The card

extension PrayerPhotos {
    /// The prayer's name and its day ("Tue, Oct 7") from a key ("2026-10-07-Asr").
    static func parts(_ key: String) -> (name: String, day: String) {
        let dayKey = String(key.prefix(10)), name = String(key.dropFirst(11))
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        let day = parser.date(from: dayKey).map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? dayKey
        return (name, day)
    }

    /// "Asr · Tue, Oct 7".
    static func caption(_ key: String) -> String {
        let p = parts(key)
        return "\(p.name) · \(p.day)"
    }

    /// Settings → Prayer photos → Show where (owner, decision prayer-photo-location A: off by default).
    static let showPlaceKey = "prayerPhotos.showPlace"
}

/// The photo the Locket / BeReal way (owner: "rounded squares for the back camera too"): the back camera's in a rounded
/// square, the front camera's small in its top corner, a rounded square too, with a white edge. A tap opens it full
/// screen (owner: "let me click on the pic to open it full screen").
struct PrayerPhotoCard: View {
    let key: String
    var width: CGFloat = 120
    /// A tap opens it full screen (off where the whole row already does something).
    var opens = true
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)
    @State private var open = false
    /// Where it sits on screen: the opened card zooms out of here and back (owner: "the zoom effect for the photo in the
    /// center of the ring").
    @State private var frame: CGRect = .zero

    var body: some View {
        PrayerPhotoFace(back: images.back, front: images.front, width: width)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            // Out in the viewer while it's open, so it's never there twice.
            .opacity(open ? 0 : 1)
            .contentShape(RoundedRectangle(cornerRadius: width * 0.22, style: .continuous))
            .onTapGesture {
                guard opens, images.back != nil else { return }
                triggerSomeVibration(type: .light)
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { open = true }
            }
            .fullScreenCover(isPresented: $open) {
                PrayerPhotoViewer(key: key, from: frame.width > 0 ? frame : nil, initial: images) {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { open = false }
                }
                .presentationBackground(.clear)
            }
            .task(id: "\(key)-\(PrayerPhotoRevision.shared.value)") { images = await PrayerPhotos.load(key) }
            .accessibilityLabel("Your \(PrayerPhotos.caption(key)) photo")
            .accessibilityAddTraits(opens ? .isButton : [])
    }
}

/// The two photos drawn the card's way (also what the full-screen view and a share are made of).
struct PrayerPhotoFace: View {
    let back: UIImage?
    let front: UIImage?
    let width: CGFloat

    var body: some View {
        let corner = width * 0.22
        let small = width * 0.34
        ZStack(alignment: .topLeading) {
            Group {
                if let back { Image(uiImage: back).resizable().scaledToFill() } else { Color.primary.opacity(0.08) }
            }
            .frame(width: width, height: width)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            if let front {
                Image(uiImage: front).resizable().scaledToFill()
                    .frame(width: small, height: small)
                    .clipShape(RoundedRectangle(cornerRadius: small * 0.26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: small * 0.26, style: .continuous)
                        .stroke(Color.white, lineWidth: max(0.75, width * 0.006)))   // thin (owner: "less thickness")
                    .padding(width * 0.05)
            }
        }
        .frame(width: width, height: width)
    }
}

/// A prayer's photo very small (the day ring's dot): the back camera's alone, a rounded square with an edge.
struct PrayerPhotoThumb: View {
    let key: String
    var size: CGFloat = 18
    var edge: Color = .white
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.primary.opacity(0.2) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).stroke(edge, lineWidth: 2))
        // A small cached thumbnail (decoding the full photo for a 20 pt dot, five times over, was wasted work).
        .task(id: "\(key)-\(PrayerPhotoRevision.shared.value)") { image = await PrayerPhotos.thumbnail(key, side: Int(size * 3)) }
    }
}

/// The photo as a card floating over the app (owner: "instead of showing it full screen on a black page … like just the
/// image. And like a modal … cute and modern"): the page blurred and dimmed behind, the photo and its footer on a dark
/// rounded card that springs in; a tap on the photo swaps front and back; Share and ✕ under it as small glass circles;
/// a tap outside or a swipe down closes it.
struct PrayerPhotoViewer: View {
    let key: String
    /// The small photo it was opened from: the card zooms out of it and back into it (one view, scaled and moved).
    var from: CGRect? = nil
    let onClose: () -> Void
    @State private var images: (back: UIImage?, front: UIImage?)
    /// The card's own place, measured once; until then it isn't drawn (it would flash full size).
    @State private var cardFrame: CGRect?

    init(key: String, from: CGRect? = nil, initial: (back: UIImage?, front: UIImage?) = (nil, nil),
         onClose: @escaping () -> Void) {
        self.key = key
        self.from = from
        self.onClose = onClose
        _images = State(initialValue: initial)
        _share = State(initialValue: PrayerShareOptions(key: key))
    }

    private var dragDistance: CGFloat { hypot(drag.width, drag.height) }
    @State private var place: String?
    @State private var shown = false
    @State private var closing = false
    /// The card follows the finger anywhere (owner: "moving it naturally with my finger, not just rigid down").
    @State private var drag: CGSize = .zero
    /// Share's options, faded up at the bottom over the page (owner: not a new page).
    @State private var share: PrayerShareOptions
    @State private var sharing = false
    @AppStorage(PrayerPhotos.showPlaceKey) private var showPlace = false
    @Environment(\.modelContext) private var context

    private func lookUpPlace() async {
        place = showPlace ? await PrayerPhotos.place(for: key, in: context) : nil
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 72, 420)
            ZStack {
                // The page behind, blurred and dimmed; a tap there closes.
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.25))
                    .ignoresSafeArea()
                    .opacity(shown ? 1 - min(dragDistance / 400, 0.6) : 0)
                    // A tap on the page around it always closes, share options open or not (owner).
                    .onTapGesture { close() }
                VStack(spacing: 22) {
                    // Sharing: the card shows what will be sent.
                    PrayerPhotoFramed(back: images.back, front: images.front, key: key,
                                      place: sharing ? (share.addPlace ? share.shownPlace : nil) : place,
                                      score: sharing && share.addScore ? share.score : nil,
                                      tagOpacity: shown ? 1 : 0, width: width)
                        .shadow(color: .black.opacity(shown ? 0.35 : 0), radius: 30, y: 14)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { rect in
                            guard cardFrame == nil, rect.width > 1 else { return }
                            cardFrame = rect
                            zoomIn()
                        }
                        .scaleEffect(zoom.scale)
                        .offset(x: zoom.dx, y: zoom.dy)
                        .opacity(from != nil && cardFrame == nil ? 0 : 1)
                        .onTapGesture {
                            guard images.front != nil else { return }
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy(duration: 0.25)) { images = (images.front, images.back) }
                            PrayerPhotoMain.shared.toggle(key)
                        }
                    HStack(spacing: 18) {
                        Button { setSharing(!sharing) } label: {
                            circleIcon(sharing ? "square.and.arrow.up.fill" : "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Share")
                        Button(action: close) { circleIcon("xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                    }
                    .opacity(dragDistance > 10 || !shown ? 0 : 1)
                }
                // Room for the share options under it.
                .offset(y: sharing ? -110 : 0)
                .offset(drag)
                .scaleEffect(1 - min(dragDistance / 1400, 0.22))
                // Opened from a small photo: the card zooms (above); else the old spring-in.
                .scaleEffect(from == nil && !shown ? 0.86 : 1)
                .opacity(from == nil && !shown ? 0 : 1)
                .gesture(DragGesture()
                    .onChanged { value in if !sharing { drag = value.translation } }
                    .onEnded { value in
                        guard !sharing else { return }
                        let far = hypot(value.translation.width, value.translation.height)
                        let flung = hypot(value.predictedEndTranslation.width, value.predictedEndTranslation.height)
                        if far > 120 || flung > 280 { close() }
                        else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = .zero } }
                    })
                if sharing {
                    VStack(spacing: 12) {
                        PrayerShareControls(options: share)
                        PrayerShareButton(options: share)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial))
                    .padding(.horizontal, 14).padding(.bottom, 10)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            #if DEBUG
            print("PHOTOCARD open \(key)")
            #endif
            PrayerPhotoViewing.shared.opened()
            if from == nil { withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { shown = true } }
        }
        .onDisappear {
            #if DEBUG
            print("PHOTOCARD gone \(key) (\(closing ? "closed by the user" : "closed from under it"))")
            #endif
            PrayerPhotoViewing.shared.closed()
        }
        .task { if images.back == nil { images = await PrayerPhotos.load(key) } }
        .task(id: showPlace) { await lookUpPlace() }
        .task(id: "\(sharing)|\(share.signature)|\(images.back?.hash ?? 0)") { if sharing { share.render(images) } }
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 50)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    /// While hidden, the card sits exactly on the small photo (its size and place); shown, where it belongs.
    private var zoom: (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        guard !shown, let from, let card = cardFrame, card.width > 0 else { return (1, 0, 0) }
        return (from.width / card.width, from.midX - card.midX, from.midY - card.midY)
    }

    private func zoomIn() {
        guard from != nil else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { shown = true }
        }
    }

    private func setSharing(_ on: Bool) {
        triggerSomeVibration(type: .light)
        if on { Task { await share.load(in: context) } }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { sharing = on }
    }

    private func close() {
        closing = true
        sharing = false
        triggerSomeVibration(type: .light)
        if from != nil, cardFrame != nil {
            // Back into the small photo, then the cover goes (and the small photo shows again in the same moment).
            withAnimation(.spring(response: 0.36, dampingFraction: 0.92)) {
                shown = false
                drag = .zero
            } completion: { onClose() }
            return
        }
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onClose() }
    }

}

/// The photo framed for opening and sharing (owner, decision prayer-photo-style C: "i like C"): just the photo, the
/// prayer's symbol, name and day (and the place, with Show where on) on a glass tag inside it, a small shukr in the
/// top corner — nothing runs past its edges.
struct PrayerPhotoFramed: View {
    let back: UIImage?
    let front: UIImage?
    let key: String
    var place: String? = nil
    /// The prayer's score as a ring in the tag (the share page's option).
    var score: Double? = nil
    /// The tag and the shukr pill fade in as an opened photo zooms out of its small square.
    var tagOpacity: Double = 1
    let width: CGFloat

    var body: some View {
        let p = PrayerPhotos.parts(key)
        PrayerPhotoFace(back: back, front: front, width: width)
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Image(systemName: prayerIcon(for: p.name)).font(.system(size: 14))
                        Text(p.name).font(.system(size: 17, weight: .medium, design: .rounded))
                    }
                    Text(p.day).font(.system(size: 12, design: .rounded)).opacity(0.75)
                    if let place {
                        Label(place, systemImage: "mappin")
                            .font(.system(size: 12, design: .rounded)).lineLimit(1).opacity(0.75)
                    }
                }
                if let score {
                    ZStack {
                        Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                        Circle().trim(from: 0, to: max(score, 0.02))
                            .stroke(PrayerScoring.color(for: score), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int((score * 100).rounded()))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .frame(width: 32, height: 32)
                }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: width * 0.8, alignment: .leading)
                .padding(width * 0.06)
                .opacity(tagOpacity)
            }
            .overlay(alignment: .topTrailing) {
                Text("shukr")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .environment(\.colorScheme, .dark)
                    .padding(width * 0.06)
                    .opacity(tagOpacity)
            }
    }
}

// MARK: - Sharing (one set of options and controls, for the share page and the opened photo's panel)

/// What goes on a shared picture (owner: shukr, the prayer and the day always; the place — the address or just the city,
/// city by default — and the score as a ring are options; "make them synched … so if we edit one in the future, the
/// other updates too"). Both share places use this and `PrayerShareControls` / `PrayerShareButton`.
@MainActor @Observable final class PrayerShareOptions {
    let key: String
    var place: String?
    var city: String?
    var score: Double?
    var addPlace = false
    var addScore = false
    var cityOnly = true
    var looked = false
    /// The picture that's sent, made again only when what's on it changes.
    var picture: UIImage?

    init(key: String) { self.key = key }

    var shownPlace: String? { cityOnly ? city ?? place : place }

    /// Changes whenever the picture would.
    var signature: String { "\(addPlace)|\(addScore)|\(cityOnly)|\(place ?? "")|\(score ?? -1)" }

    func load(in context: ModelContext) async {
        guard !looked else { return }
        score = PrayerPhotos.score(for: key, in: context)
        if let facts = PrayerPhotos.facts(for: key, in: context) {
            place = await PrayerPhotos.placeText(facts, cityOnly: false)
            city = await PrayerPhotos.placeText(facts, cityOnly: true)
        }
        #if DEBUG
        // `-demoShareScore 0.86`: a score and a place for the stand-in photos (no prayer rows behind them).
        let demo = UserDefaults.standard.double(forKey: "demoShareScore")
        if demo > 0 { score = score ?? demo; place = place ?? "Masjid Al-Noor"; city = city ?? "Cary, NC" }
        #endif
        addPlace = UserDefaults.standard.bool(forKey: PrayerPhotos.showPlaceKey) && place != nil
        #if DEBUG
        if demo > 0 { addPlace = true; addScore = true }   // the simulator's taps miss Toggles
        #endif
        looked = true
    }

    func framed(_ images: (back: UIImage?, front: UIImage?), width: CGFloat) -> PrayerPhotoFramed {
        PrayerPhotoFramed(back: images.back, front: images.front, key: key,
                          place: addPlace ? shownPlace : nil, score: addScore ? score : nil, width: width)
    }

    func render(_ images: (back: UIImage?, front: UIImage?)) {
        guard images.back != nil else { return }
        let renderer = ImageRenderer(content: framed(images, width: 1080 / 3).padding(18))
        renderer.scale = 3
        if let image = renderer.uiImage { picture = image }
    }
}

/// Location (with Address / City) and Prayer score, as toggles.
struct PrayerShareControls: View {
    @Bindable var options: PrayerShareOptions

    var body: some View {
        VStack(spacing: 0) {
            option("Location", detail: options.looked && options.place == nil ? "Not recorded for this prayer" : options.shownPlace,
                   isOn: $options.addPlace, enabled: options.place != nil)
            if options.addPlace && options.city != nil {
                Picker("Show", selection: $options.cityOnly) {
                    Text("City").tag(true)
                    Text("Address").tag(false)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
            Divider().padding(.leading, 16)
            option("Prayer score",
                   detail: options.score.map { PrayerScoring.summary(for: $0) } ?? (options.looked ? "Not marked" : nil),
                   isOn: $options.addScore, enabled: options.score != nil)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
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
}

/// The big Share button: the system share sheet with the picture as the options make it.
struct PrayerShareButton: View {
    let options: PrayerShareOptions

    var body: some View {
        if let picture = options.picture {
            ShareLink(item: Image(uiImage: picture),
                      preview: SharePreview(PrayerPhotos.caption(options.key), image: Image(uiImage: picture))) {
                label
            }
        } else {
            label.opacity(0.5)
        }
    }

    private var label: some View {
        Label("Share", systemImage: "square.and.arrow.up")
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Capsule().fill(Color.sage))
    }
}

// MARK: - The camera

/// Both cameras at once where the iPhone can (iPhone XS and later: `AVCaptureMultiCamSession`), else the back camera.
/// Set up and run on its own queue (the app's rule for capture sessions: never on the main thread).
final class DualCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    @Published private(set) var running = false
    @Published private(set) var dual = false
    @Published private(set) var denied = false
    let backPreview = AVCaptureVideoPreviewLayer()
    let frontPreview = AVCaptureVideoPreviewLayer()
    private let queue = DispatchQueue(label: "shukr.prayerPhotos.camera")
    private var session: AVCaptureSession?
    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()
    private var backData: Data?
    private var frontData: Data?
    private var waiting = 0
    private var done: ((Data?, Data?) -> Void)?

    static var available: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { DispatchQueue.main.async { self.denied = true }; return }
            self.queue.async {
                if self.session == nil { self.configure() }
                self.session?.startRunning()
                let dual = self.session is AVCaptureMultiCamSession
                DispatchQueue.main.async { self.running = self.session != nil; self.dual = dual }
            }
        }
    }

    func stop() {
        queue.async { self.session?.stopRunning() }
    }

    private func configure() {
        backPreview.videoGravity = .resizeAspectFill
        frontPreview.videoGravity = .resizeAspectFill
        if AVCaptureMultiCamSession.isMultiCamSupported, configureDual() { return }
        configureSingle()
    }

    private func configureDual() -> Bool {
        let s = AVCaptureMultiCamSession()
        s.beginConfiguration()
        defer { s.commitConfiguration() }
        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let backIn = try? AVCaptureDeviceInput(device: back), s.canAddInput(backIn),
              let frontIn = try? AVCaptureDeviceInput(device: front) else { return false }
        s.addInputWithNoConnections(backIn)
        guard s.canAddInput(frontIn) else { return false }
        s.addInputWithNoConnections(frontIn)
        guard s.canAddOutput(backOutput), s.canAddOutput(frontOutput) else { return false }
        s.addOutputWithNoConnections(backOutput)
        s.addOutputWithNoConnections(frontOutput)
        guard let backPort = backIn.ports(for: .video, sourceDeviceType: back.deviceType, sourceDevicePosition: .back).first,
              let frontPort = frontIn.ports(for: .video, sourceDeviceType: front.deviceType, sourceDevicePosition: .front).first
        else { return false }
        let backPhoto = AVCaptureConnection(inputPorts: [backPort], output: backOutput)
        let frontPhoto = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
        guard s.canAddConnection(backPhoto), s.canAddConnection(frontPhoto) else { return false }
        s.addConnection(backPhoto)
        s.addConnection(frontPhoto)
        if frontPhoto.isVideoMirroringSupported {
            frontPhoto.automaticallyAdjustsVideoMirroring = false
            frontPhoto.isVideoMirrored = true   // the selfie as you saw it
        }
        backPreview.setSessionWithNoConnection(s)
        frontPreview.setSessionWithNoConnection(s)
        let backShow = AVCaptureConnection(inputPort: backPort, videoPreviewLayer: backPreview)
        let frontShow = AVCaptureConnection(inputPort: frontPort, videoPreviewLayer: frontPreview)
        guard s.canAddConnection(backShow), s.canAddConnection(frontShow) else { return false }
        s.addConnection(backShow)
        s.addConnection(frontShow)
        if frontShow.isVideoMirroringSupported {
            frontShow.automaticallyAdjustsVideoMirroring = false
            frontShow.isVideoMirrored = true
        }
        session = s
        return true
    }

    private func configureSingle() {
        let s = AVCaptureSession()
        s.beginConfiguration()
        s.sessionPreset = .photo
        if let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: back), s.canAddInput(input), s.canAddOutput(backOutput) {
            s.addInput(input)
            s.addOutput(backOutput)
        }
        s.commitConfiguration()
        backPreview.session = s
        session = s
    }

    /// Both photos at once (or the back one); `completion` on the main queue with what came back.
    func capture(_ completion: @escaping (Data?, Data?) -> Void) {
        queue.async {
            self.backData = nil
            self.frontData = nil
            self.done = completion
            let dual = self.session is AVCaptureMultiCamSession
            self.waiting = dual ? 2 : 1
            self.backOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            if dual { self.frontOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self) }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        queue.async {
            let data = photo.fileDataRepresentation()
            if output === self.frontOutput { self.frontData = data } else { self.backData = data }
            self.waiting -= 1
            guard self.waiting == 0, let done = self.done else { return }
            self.done = nil
            let back = self.backData, front = self.frontData
            DispatchQueue.main.async { done(back, front) }
        }
    }
}

/// A preview layer in SwiftUI.
private struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer
    final class Host: UIView {
        var preview: AVCaptureVideoPreviewLayer?
        override func layoutSubviews() { super.layoutSubviews(); preview?.frame = bounds }
    }
    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.backgroundColor = .black
        view.layer.addSublayer(layer)
        view.preview = layer
        return view
    }
    func updateUIView(_ view: Host, context: Context) { view.setNeedsLayout() }
}

// MARK: - The capture screen

/// Full screen: the back camera, the front one in its corner, the prayer's line on top, one shutter — then the photo
/// (the card's look) with Retake and Save.
struct PrayerPhotoCapture: View {
    let target: PrayerPhotoTarget
    let onClose: () -> Void
    @StateObject private var camera = DualCamera()
    @State private var shot: (back: UIImage, front: UIImage?, backData: Data, frontData: Data?)?
    @State private var saving = false
    /// The selfie as the main picture (a tap on the review swaps them; kept with the photo).
    @State private var selfieMain = false
    /// A few words with it, optional (the Journal shows them under the photo).
    @State private var note = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let shot {
                review(shot)
            } else {
                viewfinder
            }
        }
        .overlay(alignment: .top) {
            HStack {
                Text(target.title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button { camera.stop(); onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .onAppear { if DualCamera.available { camera.start() } }
        .onDisappear { camera.stop() }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var viewfinder: some View {
        VStack(spacing: 28) {
            ZStack(alignment: .topLeading) {
                Group {
                    if camera.denied {
                        message("Camera is off for shukr", "Settings → shukr → Camera")
                    } else if DualCamera.available {
                        CameraPreview(layer: camera.backPreview)
                    } else {
                        message("No camera here", "Take this on your iPhone")
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 60, style: .continuous))
                if camera.dual {
                    CameraPreview(layer: camera.frontPreview)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white, lineWidth: 2))
                        .padding(16)
                }
            }
            .padding(.horizontal, 12)
            Button(action: shoot) {
                Circle().stroke(.white, lineWidth: 5)
                    .frame(width: 78, height: 78)
                    .overlay(Circle().fill(.white).padding(9))
            }
            .accessibilityLabel("Take photo")
            .disabled(!canShoot)
            .opacity(canShoot ? 1 : 0.4)
        }
        .padding(.top, 60)
    }

    private var canShoot: Bool {
        #if DEBUG
        if !DualCamera.available { return true }   // the simulator: a made-up photo, to walk the flow
        #endif
        return camera.running
    }

    private func message(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "camera").font(.system(size: 30, weight: .light))
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.08))
    }

    private func review(_ shot: (back: UIImage, front: UIImage?, backData: Data, frontData: Data?)) -> some View {
        VStack(spacing: 28) {
            GeometryReader { geo in
                PrayerPhotoFace(back: selfieMain ? shot.front ?? shot.back : shot.back,
                                front: selfieMain ? shot.back : shot.front, width: geo.size.width)
                    .onTapGesture {
                        guard shot.front != nil else { return }
                        triggerSomeVibration(type: .light)
                        withAnimation(.snappy(duration: 0.25)) { selfieMain.toggle() }
                    }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 12)
            TextField("Add a note", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.12)))
                .padding(.horizontal, 24)
            HStack(spacing: 14) {
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeOut(duration: 0.2)) { self.shot = nil }
                } label: {
                    Text("Retake").frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(.white.opacity(0.16)))
                }
                Button {
                    guard !saving else { return }
                    saving = true
                    triggerSomeVibration(type: .success)
                    Task {
                        await PrayerPhotos.save(target.key, back: shot.backData, front: shot.frontData)
                        PrayerPhotoMain.shared.set(target.key, selfie: selfieMain && shot.frontData != nil)
                        PrayerPhotos.setNote(target.key, note)
                        camera.stop()
                        onClose()
                    }
                } label: {
                    Text("Save").frame(maxWidth: .infinity).frame(height: 52)
                        .background(Capsule().fill(Color.sage))
                }
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
        }
        .padding(.top, 60)
    }

    private func shoot() {
        #if DEBUG
        print("PHOTOCAM shoot available=\(DualCamera.available) running=\(camera.running)")
        #endif
        triggerSomeVibration(type: .medium)
        #if DEBUG
        if !DualCamera.available { take(Self.demoPhoto(.systemTeal), Self.demoPhoto(.systemOrange)); return }
        #endif
        camera.capture { back, front in take(back, front) }
    }

    private func take(_ back: Data?, _ front: Data?) {
        #if DEBUG
        print("PHOTOCAM take back=\(back?.count ?? -1) front=\(front?.count ?? -1)")
        #endif
        guard let back, let backImage = UIImage(data: back) else { return }
        let frontImage = front.flatMap(UIImage.init(data:))
        withAnimation(.easeOut(duration: 0.2)) { shot = (backImage, frontImage, back, front) }
    }

    #if DEBUG
    /// The simulator has no camera: a plain photo of a colour, to walk the flow.
    static func demoPhoto(_ color: UIColor) -> Data? {
        let size = CGSize(width: 1200, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let top = color == .systemTeal ? UIColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1) : UIColor(red: 0.95, green: 0.75, blue: 0.55, alpha: 1)
            let bottom = color == .systemTeal ? UIColor(red: 0.85, green: 0.45, blue: 0.35, alpha: 1) : UIColor(red: 0.80, green: 0.50, blue: 0.40, alpha: 1)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            let symbol = color == .systemTeal ? "moon.stars.fill" : "face.smiling.inverse"
            if let img = UIImage(systemName: symbol)?.withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal) {
                img.draw(in: CGRect(x: 380, y: 300, width: 440, height: 440))
            }
        }.jpegData(compressionQuality: 0.85)
    }
    #endif
}

/// Which picture is the main one, per photo (owner: "however they last toggled the main photo, save it as such … if
/// they want selfie to be the primary pic"): the keys whose selfie leads, in UserDefaults. Set by a tap that swaps the
/// two — in the camera's review, the hold editor's photo, Memories' pile and the share page; nothing asks to save.
@MainActor @Observable final class PrayerPhotoMain {
    static let shared = PrayerPhotoMain()
    nonisolated private static let defaultsKey = "prayerPhotos.selfieMain"
    private(set) var selfieMain: Set<String> = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])

    func isSelfie(_ key: String) -> Bool { selfieMain.contains(key) }

    func set(_ key: String, selfie: Bool) {
        guard selfie != selfieMain.contains(key) else { return }
        if selfie { selfieMain.insert(key) } else { selfieMain.remove(key) }
        UserDefaults.standard.set(Array(selfieMain), forKey: Self.defaultsKey)
        PrayerPhotoRevision.shared.bump()
    }

    func toggle(_ key: String) { set(key, selfie: !isSelfie(key)) }

    /// For the loaders, off the main thread.
    nonisolated static func selfieIsMain(_ key: String) -> Bool {
        UserDefaults.standard.stringArray(forKey: defaultsKey)?.contains(key) ?? false
    }
}

/// The photos marked with a heart (Memories' Favorites filter): their keys, in UserDefaults.
@MainActor @Observable final class PrayerPhotoFavorites {
    static let shared = PrayerPhotoFavorites()
    private static let defaultsKey = "prayerPhotos.favorites"
    private(set) var keys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])

    func contains(_ key: String) -> Bool { keys.contains(key) }

    func set(_ key: String, _ on: Bool) {
        guard on != keys.contains(key) else { return }
        if on { keys.insert(key) } else { keys.remove(key) }
        UserDefaults.standard.set(Array(keys), forKey: Self.defaultsKey)
    }

    func toggle(_ key: String) { set(key, !contains(key)) }
}

/// The names of the places prayers were marked at, for search ("Cary, NC"): looked up once per place (about a km) from
/// the prayer's own spot and remembered as words only — no location is copied (owner: "can't we just use the address of
/// the prayer that was marked?").
@MainActor enum PrayerPlaceNames {
    private static let defaultsKey = "prayerPhotos.placeNames"
    private static var names: [String: String] = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    private static var looking = false

    static func key(_ c: CLLocationCoordinate2D) -> String { String(format: "%.2f,%.2f", c.latitude, c.longitude) }
    static func name(_ c: CLLocationCoordinate2D) -> String? { names[key(c)] }

    /// Looks up the places not named yet, one at a time (Apple's lookup is rate-limited); `onEach` after each new name.
    static func fill(_ spots: [CLLocationCoordinate2D], onEach: @escaping () -> Void) {
        guard !looking else { return }
        var seen = Set<String>()
        let missing = spots.filter { names[key($0)] == nil && seen.insert(key($0)).inserted }
        guard !missing.isEmpty else { return }
        looking = true
        Task {
            for spot in missing {
                if let city = await PrayerSpotAddress.city(spot) {
                    names[key(spot)] = city
                    UserDefaults.standard.set(names, forKey: defaultsKey)
                    onEach()
                }
                try? await Task.sleep(for: .milliseconds(600))
            }
            looking = false
        }
    }
}

/// "42 photos · 9.3 MB" in Memories' settings.
struct PrayerPhotoStorageRow: View {
    @State private var usage: (count: Int, bytes: Int64)?
    var body: some View {
        LabeledContent("Space used") {
            if let usage {
                Text(usage.count == 0 ? "No photos" :
                     "\(usage.count == 1 ? "1 photo" : "\(usage.count) photos") · \(usage.bytes.formatted(.byteCount(style: .file)))")
            }
        }
        .task(id: PrayerPhotoRevision.shared.value) { usage = await PrayerPhotos.usage() }
    }
}
