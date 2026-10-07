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

    static func url(_ key: String, front: Bool) -> URL {
        directory.appendingPathComponent("\(key)-\(front ? "front" : "back").jpg")
    }

    #if DEBUG
    /// The most recently saved photo's key (`-demoPhotoViewer`).
    static var newestKey: String? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let backs = files.filter { $0.lastPathComponent.hasSuffix("-back.jpg") }
        let newest = backs.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        return newest.map { String($0.lastPathComponent.dropLast("-back.jpg".count)) }
    }
    #endif

    static func has(_ key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(key, front: false).path)
    }

    /// Downscaled and written off the main thread; the views showing photos redraw after.
    static func save(_ key: String, back: Data, front: Data?) async {
        let backJPEG = await jpeg(back, maxPixels: 1600)
        let frontJPEG: Data? = if let front { await jpeg(front, maxPixels: 900) } else { nil }
        await Task.detached(priority: .userInitiated) {
            if let backJPEG { try? backJPEG.write(to: url(key, front: false), options: .atomic) }
            if let frontJPEG {
                try? frontJPEG.write(to: url(key, front: true), options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url(key, front: true))
            }
        }.value
        await PrayerPhotoRevision.shared.bump()
    }

    static func delete(_ key: String) {
        try? FileManager.default.removeItem(at: url(key, front: false))
        try? FileManager.default.removeItem(at: url(key, front: true))
        Task { @MainActor in PrayerPhotoRevision.shared.bump() }
    }

    /// Decoded off the main thread, ready to draw.
    static func load(_ key: String) async -> (back: UIImage?, front: UIImage?) {
        await Task.detached(priority: .userInitiated) {
            func image(_ front: Bool) -> UIImage? {
                guard let data = try? Data(contentsOf: url(key, front: front)) else { return nil }
                return UIImage(data: data)?.preparingForDisplay()
            }
            return (image(false), image(true))
        }.value
    }

    /// The photo the right way up, its longest side at most `maxPixels`, as a JPEG.
    static func jpeg(_ data: Data, maxPixels: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixels]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg).jpegData(compressionQuality: 0.82)
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
    func bump() { value += 1 }
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

    var body: some View {
        PrayerPhotoFace(back: images.back, front: images.front, width: width)
            .contentShape(RoundedRectangle(cornerRadius: width * 0.22, style: .continuous))
            .onTapGesture {
                guard opens, images.back != nil else { return }
                triggerSomeVibration(type: .light)
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { open = true }
            }
            .fullScreenCover(isPresented: $open) {
                PrayerPhotoViewer(key: key) {
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
        .task(id: "\(key)-\(PrayerPhotoRevision.shared.value)") { image = await PrayerPhotos.load(key).back }
    }
}

/// The photo as a card floating over the app (owner: "instead of showing it full screen on a black page … like just the
/// image. And like a modal … cute and modern"): the page blurred and dimmed behind, the photo and its footer on a dark
/// rounded card that springs in; a tap on the photo swaps front and back; Share and ✕ under it as small glass circles;
/// a tap outside or a swipe down closes it.
struct PrayerPhotoViewer: View {
    let key: String
    let onClose: () -> Void
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)
    @State private var swapped = false
    @State private var place: String?
    @State private var shown = false
    @State private var closing = false
    @State private var drag: CGFloat = 0
    @AppStorage(PrayerPhotos.showPlaceKey) private var showPlace = false
    @Environment(\.modelContext) private var context

    /// Where it was prayed: the masjid's name, else the spot's address (only with Show where on).
    private func lookUpPlace() async {
        guard showPlace else { place = nil; return }
        let dayKey = String(key.prefix(10)), name = String(key.dropFirst(11))
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.prayerDayKey == dayKey && $0.name == name }))) ?? []
        guard let row = rows.first(where: \.isCompleted) ?? rows.first else { return }
        if let masjid = row.mosqueName, !masjid.isEmpty { place = masjid; return }
        guard let lat = row.latPrayedAt, let lon = row.longPrayedAt else { return }
        place = await PrayerSpotAddress.lookUp(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 72, 420)
            ZStack {
                // The page behind, blurred and dimmed; a tap there closes.
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.25))
                    .ignoresSafeArea()
                    .opacity(shown ? 1 - min(drag / 400, 0.6) : 0)
                    .onTapGesture { close() }
                VStack(spacing: 22) {
                    PrayerPhotoFramed(back: swapped ? images.front : images.back,
                                      front: swapped ? images.back : images.front,
                                      key: key, place: place, width: width)
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
                        .onTapGesture {
                            guard images.front != nil else { return }
                            triggerSomeVibration(type: .light)
                            withAnimation(.snappy(duration: 0.25)) { swapped.toggle() }
                        }
                    HStack(spacing: 18) {
                        if let shared = sharedImage() {
                            ShareLink(item: Image(uiImage: shared),
                                      preview: SharePreview(PrayerPhotos.caption(key), image: Image(uiImage: shared))) {
                                circleIcon("square.and.arrow.up")
                            }
                            .tint(.primary)
                            .accessibilityLabel("Share")
                        }
                        Button(action: close) { circleIcon("xmark") }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                    }
                    .opacity(drag > 10 ? 0 : 1)
                }
                .offset(y: drag)
                .scaleEffect(shown ? 1 : 0.86)
                .opacity(shown ? 1 : 0)
                .gesture(DragGesture()
                    .onChanged { drag = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 260 { close() }
                        else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 } }
                    })
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            #if DEBUG
            print("PHOTOCARD open \(key)")
            #endif
            PrayerPhotoViewing.shared.opened()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { shown = true }
        }
        .onDisappear {
            #if DEBUG
            print("PHOTOCARD gone \(key) (\(closing ? "closed by the user" : "closed from under it"))")
            #endif
            PrayerPhotoViewing.shared.closed()
        }
        .task { images = await PrayerPhotos.load(key) }
        .task(id: showPlace) { await lookUpPlace() }
    }

    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 50)
            .background(Circle().fill(.regularMaterial))
            .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func close() {
        closing = true
        triggerSomeVibration(type: .light)
        withAnimation(.easeIn(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onClose() }
    }

    /// The branded picture as an image, for Share (the same dark card).
    @MainActor private func sharedImage() -> UIImage? {
        guard images.back != nil else { return nil }
        let w: CGFloat = 1080 / 3
        let renderer = ImageRenderer(content: PrayerPhotoFramed(back: images.back, front: images.front,
                                                                key: key, place: place, width: w)
            .padding(18))
        renderer.scale = 3
        return renderer.uiImage
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
    let width: CGFloat

    var body: some View {
        let p = PrayerPhotos.parts(key)
        PrayerPhotoFace(back: back, front: front, width: width)
            .overlay(alignment: .bottomLeading) {
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
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: width * 0.8, alignment: .leading)
                .padding(width * 0.06)
            }
            .overlay(alignment: .topTrailing) {
                Text("shukr")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .environment(\.colorScheme, .dark)
                    .padding(width * 0.06)
            }
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
                PrayerPhotoFace(back: shot.back, front: shot.front, width: geo.size.width)
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 12)
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
