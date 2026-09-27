//
//  ZikrMedia.swift
//  shukr
//
//  A zikr's photo and voice memo, for learning it (2026-09-27, notes #17; `MantraModel.imageData`
//  / `audioData`, schema 2.5.0). Shown on the zikr card in the same box as the notes — the left
//  column's doc.text / waveform / photo icons swap what's in it (`MantraCardFields`) — and on the
//  pause card as a small ▶︎ and a tap-to-expand thumbnail (`ZikrMediaStrip`).
//  - Voice memo: AVAudioRecorder (AAC .m4a, a live level meter, ≤ 2 min), re-record / delete;
//    AVAudioPlayer with a ring-style ▶︎, 0.75× and loop. The session is deactivated with
//    `.notifyOthersOnDeactivation` afterwards, so the user's music comes back.
//  - Photo: PhotosPicker or the camera, downscaled to ~1200 px JPEG; tap → full screen, zoomable.
//

import SwiftUI
import AVFoundation
import PhotosUI
import SwiftData

// MARK: - Recording and playback

@MainActor @Observable
final class ZikrAudio: NSObject, AVAudioPlayerDelegate {
    static let maxSeconds: TimeInterval = 120

    enum State: Equatable { case idle, recording, playing, paused }
    private(set) var state: State = .idle
    /// 0…1, the recording's live level (for the meter).
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var slow = false { didSet { player?.rate = slow ? 0.75 : 1 } }
    var loop = false { didSet { player?.numberOfLoops = loop ? -1 : 0 } }
    /// The microphone was refused (the panel says so, with a way to Settings).
    private(set) var micDenied = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var fileURL: URL { FileManager.default.temporaryDirectory.appending(path: "zikr-memo.m4a") }

    var progress: Double { duration > 0 ? min(elapsed / duration, 1) : 0 }

    // Record
    func startRecording() async {
        stopPlaying()
        let allowed: Bool = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard allowed else { micDenied = true; return }
        micDenied = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            try? FileManager.default.removeItem(at: fileURL)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                           AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
            let r = try AVAudioRecorder(url: fileURL, settings: settings)
            r.isMeteringEnabled = true
            r.record(forDuration: Self.maxSeconds)
            recorder = r
            state = .recording
            elapsed = 0
            startTicker()
        } catch {
            print("❌ zikr memo record: \(error.localizedDescription)")
            endSession()
        }
    }

    /// Stops and returns the recording (nil if nothing usable).
    func stopRecording() -> Data? {
        guard let r = recorder else { return nil }
        let length = r.currentTime
        r.stop()
        recorder = nil
        stopTicker()
        state = .idle
        level = 0
        endSession()
        guard length > 0.4 || elapsed > 0.4 else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    // Play
    func togglePlay(_ data: Data) {
        switch state {
        case .playing: player?.pause(); state = .paused; stopTicker()
        case .paused: resume()
        default: play(data)
        }
    }
    private func play(_ data: Data) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.enableRate = true
            p.rate = slow ? 0.75 : 1
            p.numberOfLoops = loop ? -1 : 0
            p.play()
            player = p
            duration = p.duration
            state = .playing
            startTicker()
        } catch {
            print("❌ zikr memo play: \(error.localizedDescription)")
            endSession()
        }
    }
    private func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        state = .playing
        startTicker()
    }
    func stopPlaying() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        stopTicker()
        state = .idle
        elapsed = 0
        endSession()
    }
    /// The memo's length without playing it (for "0:14").
    static func length(of data: Data) -> TimeInterval { (try? AVAudioPlayer(data: data))?.duration ?? 0 }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlaying() }
    }

    // Plumbing
    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    private func tick() {
        if let r = recorder {
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)            // -160…0
            level = max(0, min(1, (db + 50) / 50))
            elapsed = r.currentTime
            if !r.isRecording { _ = stopRecording() }          // hit the 2 min cap
        } else if let p = player {
            elapsed = p.currentTime
        }
    }
    /// Hand audio back: other apps' music resumes.
    private func endSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

func mmss(_ t: TimeInterval) -> String {
    let s = max(Int(t.rounded()), 0)
    return String(format: "%d:%02d", s / 60, s % 60)
}

/// ▶︎ / ❚❚ inside a thin progress ring — the app's circle language.
struct RingPlayButton: View {
    let playing: Bool
    let progress: Double
    var size: CGFloat = 52
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(progress, 0.001))
                .stroke(Color.sage, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0 ? 1 : 0)
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(Color.sage)
                .offset(x: playing ? 0 : size * 0.03)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - The memo panel (inside the card's box)

struct VoiceMemoPanel: View {
    @Binding var audio: Data?
    @State private var engine = ZikrAudio()
    @State private var length: TimeInterval = 0

    var body: some View {
        Group {
            if engine.state == .recording {
                recording
            } else if let audio {
                player(audio)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if let audio { length = ZikrAudio.length(of: audio) } }
        .onChange(of: audio) { _, new in length = new.map(ZikrAudio.length(of:)) ?? 0 }
        .onDisappear {
            if engine.state == .recording { audio = engine.stopRecording() ?? audio }
            engine.stopPlaying()
        }
    }

    private var empty: some View {
        Button {
            Task { await engine.startRecording() }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.sage)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Color.sage.opacity(0.14)))
                Text(engine.micDenied ? "Microphone is off · Settings" : "Tap to record")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("how it's said — you, a teacher, a friend")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            if engine.micDenied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
    }

    private var recording: some View {
        HStack(spacing: 14) {
            Button {
                if let data = engine.stopRecording() {
                    audio = data
                    triggerSomeVibration(type: .success)
                }
            } label: {
                ZStack {
                    Circle().fill(Color.red.opacity(0.14))
                    RoundedRectangle(cornerRadius: 4).fill(Color.red).frame(width: 16, height: 16)
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
            VStack(alignment: .leading, spacing: 6) {
                LevelMeter(level: engine.level)
                    .frame(height: 26)
                Text("\(mmss(engine.elapsed)) / \(mmss(ZikrAudio.maxSeconds))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
    }

    private func player(_ data: Data) -> some View {
        HStack(spacing: 14) {
            Button { engine.togglePlay(data) } label: {
                RingPlayButton(playing: engine.state == .playing, progress: engine.progress)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.state == .playing ? "Pause" : "Play voice memo")
            VStack(alignment: .leading, spacing: 8) {
                Text(engine.state == .idle ? "voice memo · \(mmss(length))" : "\(mmss(engine.elapsed)) / \(mmss(engine.duration))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    chip("0.75×", on: engine.slow) { engine.slow.toggle() }
                    chip(nil, symbol: "repeat", on: engine.loop) { engine.loop.toggle() }
                    Spacer(minLength: 0)
                    Menu {
                        Button("Record again", systemImage: "mic") {
                            engine.stopPlaying()
                            Task { await engine.startRecording() }
                        }
                        Button("Delete voice memo", systemImage: "trash", role: .destructive) {
                            engine.stopPlaying()
                            audio = nil
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 26)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .tint(.secondary)
                }
            }
        }
        .padding(.horizontal, 6)
    }

    private func chip(_ title: String?, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol) } else { Text(title ?? "") }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(on ? Color.sage : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }
}

/// Bars that follow the recording's level.
private struct LevelMeter: View {
    let level: Float
    @State private var history: [Float] = Array(repeating: 0, count: 28)
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, v in
                Capsule().fill(Color.red.opacity(0.75))
                    .frame(width: 3, height: max(3, CGFloat(v) * 26))
            }
        }
        .animation(.linear(duration: 0.05), value: history)
        .onChange(of: level) { _, v in
            history.removeFirst()
            history.append(v)
        }
    }
}

// MARK: - The photo panel

struct ZikrPhotoPanel: View {
    @Binding var image: Data?
    @State private var pick: PhotosPickerItem?
    @State private var showCamera = false
    @State private var viewing = false

    var body: some View {
        Group {
            if let image, let ui = UIImage(data: image) {
                Button { viewing = true } label: {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.35)))
                                .padding(6)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    PhotosPicker(selection: $pick, matching: .images) { Label("Choose another photo", systemImage: "photo") }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take a photo", systemImage: "camera") { showCamera = true }
                    }
                    Button("Remove photo", systemImage: "trash", role: .destructive) { self.image = nil }
                }
                .fullScreenCover(isPresented: $viewing) { ZikrPhotoViewer(image: ui) }
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let small = downscaledJPEG(data) {
                    image = small
                }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in image = downscaledJPEG(data) }.ignoresSafeArea()
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            HStack(spacing: 22) {
                PhotosPicker(selection: $pick, matching: .images) {
                    emptyButton("photo.on.rectangle", "Add a photo")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { emptyButton("camera", "Take one") }
                }
            }
            .buttonStyle(.plain)
            Text("a written dua, calligraphy, a teacher's handwriting")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 6)
    }

    private func emptyButton(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 19))
                .foregroundStyle(Color.sage)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.sage.opacity(0.14)))
            Text(title).font(.footnote).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// ~1200 px on the long side, JPEG 0.82.
func downscaledJPEG(_ data: Data, maxSide: CGFloat = 1200) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    let longest = max(image.size.width, image.size.height)
    let scale = min(1, maxSide / max(longest, 1))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return resized.jpegData(compressionQuality: 0.82)
}

/// The camera, returning the photo's data.
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.onPick(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Full screen, pinch / double-tap to zoom, ✕ to close.
struct ZikrPhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            ZoomableImage(image: image).ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .statusBarHidden()
    }
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.delegate = context.coordinator
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.backgroundColor = .clear
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        ])
        context.coordinator.imageView = view
        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        return scroll
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let scroll = g.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.01 { scroll.setZoomScale(1, animated: true); return }
            let p = g.location(in: imageView)
            let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
            scroll.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

// MARK: - On the pause card

/// The pause card's row: ▶︎ the voice memo (ring, 0.75×, loop) and a tap-to-expand thumbnail.
struct ZikrMediaStrip: View {
    let mantra: MantraModel
    @State private var engine = ZikrAudio()
    @State private var viewing = false

    var body: some View {
        if mantra.audioData != nil || mantra.imageData != nil {
            HStack(spacing: 12) {
                if let audio = mantra.audioData {
                    Button { engine.togglePlay(audio) } label: {
                        RingPlayButton(playing: engine.state == .playing, progress: engine.progress, size: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(engine.state == .playing ? "Pause" : "Play voice memo")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("voice memo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            toggle("0.75×", on: engine.slow) { engine.slow.toggle() }
                            toggle(nil, symbol: "repeat", on: engine.loop) { engine.loop.toggle() }
                        }
                    }
                }
                Spacer(minLength: 0)
                if let data = mantra.imageData, let ui = UIImage(data: data) {
                    Button { viewing = true } label: {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show photo")
                    .fullScreenCover(isPresented: $viewing) { ZikrPhotoViewer(image: ui) }
                }
            }
            .onDisappear { engine.stopPlaying() }
        }
    }

    private func toggle(_ title: String?, symbol: String? = nil, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group { if let symbol { Image(systemName: symbol) } else { Text(title ?? "") } }
                .font(.caption2.weight(.medium))
                .foregroundStyle(on ? Color.sage : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(on ? Color.sage.opacity(0.16) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
// MARK: - Simulator demo

enum ZikrMediaDemo {
    /// `-demoZikrMedia`: gives Alhamdulillah a sample photo (its Arabic, set like calligraphy), a
    /// 3 s tone as the voice memo, and notes, so the card / pause card can be screenshotted.
    @MainActor static func seed(in context: ModelContext) -> MantraModel? {
        guard let m = MantraModel.find(named: "Alhamdulillah", in: context) else { return nil }
        if m.imageData == nil {
            let size = CGSize(width: 900, height: 600)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let style = NSMutableParagraphStyle(); style.alignment = .center
                let font = UIFont(name: "KFGQPCUthmanTahaNaskh", size: 150) ?? .systemFont(ofSize: 120)
                ("ٱلْحَمْدُ لِلَّٰهِ" as NSString).draw(in: CGRect(x: 0, y: 150, width: size.width, height: 300),
                    withAttributes: [.font: font, .foregroundColor: UIColor(red: 0.2, green: 0.3, blue: 0.25, alpha: 1), .paragraphStyle: style])
            }
            m.imageData = img.jpegData(compressionQuality: 0.85)
        }
        if m.audioData == nil { m.audioData = tone(seconds: 3) }
        if m.notes.isEmpty { m.notes = "Fills the Scale. My teacher said to say it slowly, feeling each word." }
        try? context.save()
        return m
    }

    /// A soft 440 Hz tone as WAV data.
    private static func tone(seconds: Double) -> Data {
        let rate = 22_050, n = Int(Double(rate) * seconds)
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / Double(rate)
            let env = min(1, t * 8, (seconds - t) * 8)
            let v = Int16(sin(2 * .pi * 440 * t) * 6000 * env)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func u32(_ x: UInt32) { withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { withUnsafeBytes(of: x.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count)); d.append(contentsOf: Array("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count)); d.append(pcm)
        return d
    }
}
#endif
