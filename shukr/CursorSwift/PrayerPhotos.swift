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

/// The photo the BeReal / Locket way: the back camera's in a soft rounded rectangle, the front camera's small in its
/// top corner, rounded too, with a white edge; a tap swaps them.
struct PrayerPhotoCard: View {
    let key: String
    var width: CGFloat = 120
    /// The small one swaps with the big one on a tap.
    var swappable = true
    @State private var images: (back: UIImage?, front: UIImage?) = (nil, nil)
    @State private var swapped = false

    var body: some View {
        let height = width * 4 / 3
        let main = swapped ? images.front : images.back
        let inset = swapped ? images.back : images.front
        ZStack(alignment: .topLeading) {
            Group {
                if let main {
                    Image(uiImage: main).resizable().scaledToFill()
                } else {
                    Color.primary.opacity(0.08)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous))
            if let inset {
                Image(uiImage: inset).resizable().scaledToFill()
                    .frame(width: width * 0.32, height: width * 0.32 * 4 / 3)
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
                        .stroke(Color.white, lineWidth: max(1, width * 0.012)))
                    .padding(width * 0.05)
            }
        }
        .frame(width: width, height: height)
        .contentShape(RoundedRectangle(cornerRadius: width * 0.14, style: .continuous))
        .onTapGesture {
            guard swappable, images.front != nil else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.snappy(duration: 0.25)) { swapped.toggle() }
        }
        .task(id: "\(key)-\(PrayerPhotoRevision.shared.value)") { images = await PrayerPhotos.load(key) }
        .accessibilityLabel("Your prayer photo")
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
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                if camera.dual {
                    CameraPreview(layer: camera.frontPreview)
                        .frame(width: 104, height: 138)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white, lineWidth: 2))
                        .padding(14)
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
            ZStack(alignment: .topLeading) {
                Image(uiImage: shot.back).resizable().scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                if let front = shot.front {
                    Image(uiImage: front).resizable().scaledToFill()
                        .frame(width: 104, height: 138)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white, lineWidth: 2))
                        .padding(14)
                }
            }
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
        triggerSomeVibration(type: .medium)
        #if DEBUG
        if !DualCamera.available { take(Self.demoPhoto(.systemTeal), Self.demoPhoto(.systemOrange)); return }
        #endif
        camera.capture { back, front in take(back, front) }
    }

    private func take(_ back: Data?, _ front: Data?) {
        guard let back, let backImage = UIImage(data: back) else { return }
        let frontImage = front.flatMap(UIImage.init(data:))
        withAnimation(.easeOut(duration: 0.2)) { shot = (backImage, frontImage, back, front) }
    }

    #if DEBUG
    /// The simulator has no camera: a plain photo of a colour, to walk the flow.
    static func demoPhoto(_ color: UIColor) -> Data? {
        UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200)).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
        }.jpegData(compressionQuality: 0.8)
    }
    #endif
}
