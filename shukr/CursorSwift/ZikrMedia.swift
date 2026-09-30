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

/// One per card / strip. Only one engine is ever active app-wide (`active`): starting one stops
/// the other (the ✎ sheet over the pause card could play alongside the strip).
/// Every way a recording ends — Stop, the 2-min cap, a call / Siri (interruption), going to the
/// background, the sheet closing — goes through `finishRecording()`, which hands the take to
/// `onRecorded`; nothing is thrown away (2026-09-27 review).
@MainActor @Observable
final class ZikrAudio: NSObject, AVAudioPlayerDelegate, AVAudioRecorderDelegate {
    static let maxSeconds: TimeInterval = 120

    /// `.loading`: a memo is being opened on the audio queue (taps are ignored; a stop cancels it).
    enum State: Equatable { case idle, loading, recording, playing, paused }
    private(set) var state: State = .idle
    /// 0…1, the recording's live level (for the meter).
    private(set) var level: Float = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var slow = false { didSet { player?.rate = slow ? 0.75 : 1 } }
    var loop = false { didSet { player?.numberOfLoops = loop ? -1 : 0 } }
    /// The microphone was refused (the panel says so, with a way to Settings).
    private(set) var micDenied = false
    /// Where a finished take goes (set by the card: it writes the zikr's `audioData`).
    @ObservationIgnored var onRecorded: ((Data) -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let fileURL = FileManager.default.temporaryDirectory.appending(path: "zikr-memo-\(UUID().uuidString.prefix(8)).m4a")

    /// Bumped by every start and stop, so a recording or a memo that finishes starting after a
    /// stop (or a newer start) is dropped instead of playing / recording on regardless.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private static weak var active: ZikrAudio?
    /// Stop whatever is playing or recording anywhere (Resume / Finish in a session).
    static func stopAll() {
        guard let a = active else { return }
        a.finishRecording()
        a.stopPlaying()
    }

    var progress: Double { duration > 0 ? min(elapsed / duration, 1) : 0 }

    override init() {
        super.init()
        let nc = NotificationCenter.default
        observers = [
            nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init) == .began
                MainActor.assumeIsolated { if began { self?.interrupted() } }
            },
            nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                // Headphones out → pause, as every player does.
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
                MainActor.assumeIsolated { if reason == .oldDeviceUnavailable { self?.pause() } }
            },
            nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupted() }
            },
        ]
    }

    /// Only stop observing here — the card finishes a take itself before letting go of the engine.
    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        recorder?.stop()
        ticker?.invalidate()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // Record
    func startRecording() async {
        Self.takeOver(self)
        stopPlaying()
        generation += 1
        let gen = generation
        let allowed: Bool = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard allowed else { micDenied = true; return }
        micDenied = false
        guard gen == generation else { return }     // dismissed / stopped during the prompt
        let url = fileURL
        do {
            // Session activation can block for a while (it hung the simulator's main thread), so
            // it and the recorder's setup run on the audio queue.
            let made = try await Self.onAudioQueue { () -> Unchecked<AVAudioRecorder> in
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                try? FileManager.default.removeItem(at: url)
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100,
                                               AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
                                               AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
                let r = try AVAudioRecorder(url: url, settings: settings)
                r.isMeteringEnabled = true
                guard r.record(forDuration: ZikrAudio.maxSeconds) else { throw CocoaError(.fileWriteUnknown) }
                return Unchecked(value: r)
            }
            let r = made.value
            guard gen == generation else {                // stopped meanwhile
                r.stop()
                try? FileManager.default.removeItem(at: url)
                if Self.active === self && state == .idle { endSession() }   // unless audio moved on
                return
            }
            r.delegate = self
            recorder = r
            state = .recording
            elapsed = 0
            startTicker()
        } catch {
            print("❌ zikr memo record: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            endSession()
        }
    }

    /// Ends a recording, if one is running, and hands the take (if long enough) to `onRecorded`.
    func finishRecording() {
        generation += 1
        guard let r = recorder else { return }
        let length = max(r.currentTime, elapsed)
        recorder = nil
        r.delegate = nil
        r.stop()
        stopTicker()
        state = .idle
        level = 0
        endSession()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard length > 0.4, let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        onRecorded?(data)
    }

    // Play
    func togglePlay(_ data: Data) {
        switch state {
        case .playing: pause()
        case .paused: resume()
        case .loading, .recording: break       // a second tap while it opens doesn't start another
        case .idle: play(data)
        }
    }
    private func play(_ data: Data) {
        Self.takeOver(self)
        generation += 1
        let gen = generation
        state = .loading
        Task {
            do {
                let made = try await Self.onAudioQueue { () -> Unchecked<AVAudioPlayer> in
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .spokenAudio)
                    try session.setActive(true)
                    return Unchecked(value: try AVAudioPlayer(data: data))
                }
                let p = made.value
                // Stopped (Resume, Finish, the page going) while it opened: never play late.
                guard gen == generation, state == .loading else {
                    if Self.active === self && state == .idle { endSession() }
                    return
                }
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
                if gen == generation { state = .idle }
                endSession()
            }
        }
    }
    /// Paused keeps the position, but gives the audio back so the user's music can play.
    func pause() {
        guard state == .playing else { return }
        player?.pause()
        state = .paused
        stopTicker()
        endSession()
    }
    private func resume() {
        Self.takeOver(self)
        state = .playing
        Task {
            _ = try? await Self.onAudioQueue {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            }
            guard state == .playing else { return }
            player?.play()
            startTicker()
        }
    }
    func stopPlaying() {
        let loading = state == .loading
        if loading { generation += 1 }             // cancels the memo being opened
        guard player != nil || loading else { return }
        player?.stop()
        player = nil
        stopTicker()
        state = .idle
        elapsed = 0
        endSession()
    }
    /// The memo's length without playing it (for "0:14"). Off the main thread: it parses the file.
    nonisolated static func length(of data: Data) async -> TimeInterval {
        await Task.detached(priority: .utility) { (try? AVAudioPlayer(data: data))?.duration ?? 0 }.value
    }

    /// When the memo was recorded: the creation time in its .m4a movie header (`mvhd`, seconds
    /// since 1904 — AVAudioRecorder stamps it). Nil when there isn't one (a WAV, an older memo
    /// without it); nothing is stored beside the memo (no schema change).
    nonisolated static func recordedDate(of data: Data) -> Date? {
        let bytes = [UInt8](data.prefix(min(data.count, 2_000_000)))
        let tag: [UInt8] = Array("mvhd".utf8)
        guard bytes.count > 24, let i = (4..<(bytes.count - 16)).first(where: { Array(bytes[$0..<$0 + 4]) == tag }) else { return nil }
        let version = bytes[i + 4]
        var seconds: UInt64 = 0
        let start = i + 8                                   // after the tag, version and flags
        let width = version == 1 ? 8 : 4
        guard start + width <= bytes.count else { return nil }
        for b in bytes[start..<start + width] { seconds = seconds << 8 | UInt64(b) }
        guard seconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds) - 2_082_844_800)   // 1904 → 1970
        return date > Date(timeIntervalSince1970: 1_500_000_000) && date < Date().addingTimeInterval(86_400) ? date : nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stopPlaying() }
    }
    /// The 2-min cap (record(forDuration:)) or the system ending it: keep the take.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.finishRecording() }
    }

    // Plumbing
    private static func takeOver(_ engine: ZikrAudio) {
        if let other = active, other !== engine {
            other.finishRecording()
            other.stopPlaying()
        }
        active = engine
    }
    private func interrupted() {
        finishRecording()
        pause()
    }
    private func startTicker() {
        stopTicker()
        // .common: keeps ticking while a list scrolls.
        let t = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }
    private func tick() {
        if let r = recorder {
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)            // -160…0
            level = max(0, min(1, (db + 50) / 50))
            elapsed = r.currentTime
            if !r.isRecording { finishRecording() }           // hit the cap / stopped by the system
        } else if let p = player {
            elapsed = p.currentTime
        }
    }
    /// Hand audio back: other apps' music resumes. On the audio queue, after any activation.
    private func endSession() {
        Self.audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Session activation / deactivation and player / recorder setup, in order, off the main thread.
    private static let audioQueue = DispatchQueue(label: "shukr.zikr-audio", qos: .userInitiated)
    private static func onAudioQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { c in
            audioQueue.async { c.resume(with: Result { try work() }) }
        }
    }
}

/// A cheap identity for a photo / memo blob (size + its ends), for `.task(id:)` — comparing the
/// whole Data on every render is what the id would otherwise do.
func blobKey(_ data: Data?) -> String? {
    guard let data else { return nil }
    return "\(data.count)-\(data.prefix(64).hashValue)-\(data.suffix(64).hashValue)"
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}

/// Carries an AVAudioRecorder / AVAudioPlayer back from the audio queue (used on main only after).
struct Unchecked<T>: @unchecked Sendable { let value: T }

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

/// The engine belongs to the card (`MantraCardFields`), not to this panel: switching tabs or a
/// List recycling the cell must never throw a take away. The card finishes a recording when you
/// leave the memo tab or the sheet really closes; the take arrives through `engine.onRecorded`.
struct VoiceMemoPanel: View {
    @Binding var audio: Data?
    let engine: ZikrAudio
    @State private var length: TimeInterval = 0
    /// When it was recorded, from the file itself (nil for a memo without one).
    @State private var recorded: Date?

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
        // Once per memo, off the main thread; keyed by a cheap fingerprint, not the whole blob.
        .task(id: blobKey(audio)) {
            length = await audio.asyncMap(ZikrAudio.length(of:)) ?? 0
            let data = audio
            recorded = await Task.detached(priority: .utility) { data.flatMap(ZikrAudio.recordedDate(of:)) }.value
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
                engine.finishRecording()        // the take arrives through onRecorded
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
                // No "voice memo" title (owner, note 3CA19C68: "looks dumb"): when it was recorded,
                // if the file says, and how long it is.
                Text(engine.state == .idle || engine.state == .loading ? idleLine : "\(mmss(engine.elapsed)) / \(mmss(engine.duration))")
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

    /// "Sep 29, 2026 · 0:42" (the year only when it isn't this one), else "0:42".
    private var idleLine: String {
        guard let recorded else { return mmss(length) }
        let sameYear = Calendar.current.isDate(recorded, equalTo: Date(), toGranularity: .year)
        let day = recorded.formatted(.dateTime.month(.abbreviated).day().year(sameYear ? .omitted : .defaultDigits))
        return "\(day) · \(mmss(length))"
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
    @State private var decoded: UIImage?

    var body: some View {
        Group {
            if image != nil, decoded == nil {
                Color.primary.opacity(0.04)               // decoding (a moment)
            } else if image != nil, let ui = decoded {
                Button { viewing = true } label: {
                    // The whole photo, shrunk to fit the box at its own shape (owner, note 3CA19C68).
                    Image(uiImage: ui).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {     // on the photo's own corner
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(Circle().fill(.black.opacity(0.35)))
                                .padding(6)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .task(id: blobKey(image)) { decoded = await decodedImage(image) }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let small = await downscaledJPEG(data) {
                    image = small
                }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo in
                Task { if let small = await downscaledJPEG(photo) { image = small } }
            }
            .ignoresSafeArea()
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

/// ~1200 px on the long side, JPEG 0.82 — decoded and scaled by ImageIO off the main thread
/// (a 12 MP photo decoded in the view was a visible hitch; 2026-09-27 review).
func downscaledJPEG(_ data: Data, maxSide: CGFloat = 1200) async -> Data? {
    await Task.detached(priority: .userInitiated) { jpegThumbnail(data, maxSide: maxSide) }.value
}

/// The camera's photo, straight in (no JPEG round trip first).
func downscaledJPEG(_ image: UIImage, maxSide: CGFloat = 1200) async -> Data? {
    nonisolated(unsafe) let image = image
    return await Task.detached(priority: .userInitiated) { () -> Data? in
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maxSide / max(longest, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        return (image.preparingThumbnail(of: size) ?? image).jpegData(compressionQuality: 0.82)
    }.value
}

nonisolated func jpegThumbnail(_ data: Data, maxSide: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                    kCGImageSourceCreateThumbnailWithTransform: true,
                                    kCGImageSourceShouldCacheImmediately: true,
                                    kCGImageSourceThumbnailMaxPixelSize: maxSide]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: cg).jpegData(compressionQuality: 0.82)
}

/// A stored photo decoded for display off the main thread (views keep it in @State via `.task(id:)`).
func decodedImage(_ data: Data?) async -> UIImage? {
    guard let data else { return nil }
    return await Task.detached(priority: .userInitiated) { UIImage(data: data)?.preparingForDisplay() }.value
}

/// The camera, returning the photo.
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
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
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
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
    /// The pause screen only fades on Resume (it stays mounted), so playback stops on this.
    var paused = true
    /// The pause card's top-right corner, beside ✎ (owner, 2026-09-29, #17): just ▶︎ and the photo,
    /// small; 0.75× and loop are in the play button's long-press menu.
    var compact = false
    @State private var engine = ZikrAudio()
    @State private var viewing = false
    @State private var thumbnail: UIImage?

    var body: some View {
        if compact {
            compactBody
        } else if mantra.audioData != nil || mantra.imageData != nil {
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
                if mantra.imageData != nil, let ui = thumbnail {
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
            .task(id: blobKey(mantra.imageData)) { thumbnail = await decodedImage(mantra.imageData) }
            .onDisappear { engine.stopPlaying() }
            .onChange(of: paused) { _, now in if !now { engine.stopPlaying() } }
        }
    }

    @ViewBuilder private var compactBody: some View {
        if mantra.audioData != nil || mantra.imageData != nil {
            HStack(spacing: 8) {
                if let audio = mantra.audioData {
                    Button { engine.togglePlay(audio) } label: {
                        RingPlayButton(playing: engine.state == .playing, progress: engine.progress, size: 34)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Toggle("Slower (0.75×)", isOn: Binding(get: { engine.slow }, set: { engine.slow = $0 }))
                        Toggle("Loop", isOn: Binding(get: { engine.loop }, set: { engine.loop = $0 }))
                    }
                    .accessibilityLabel(engine.state == .playing ? "Pause" : "Play voice memo")
                }
                if mantra.imageData != nil, let ui = thumbnail {
                    Button { viewing = true } label: {
                        Image(uiImage: ui).resizable().scaledToFill()
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show photo")
                    .fullScreenCover(isPresented: $viewing) { ZikrPhotoViewer(image: ui) }
                }
            }
            .task(id: blobKey(mantra.imageData)) { thumbnail = await decodedImage(mantra.imageData) }
            .onDisappear { engine.stopPlaying() }
            .onChange(of: paused) { _, now in if !now { engine.stopPlaying() } }
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
