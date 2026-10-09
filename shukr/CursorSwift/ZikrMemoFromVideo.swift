//
//  ZikrMemoFromVideo.swift
//  shukr
//
//  A voice memo taken from a video (owner, 2026-10-08: "an option to extract audio from a video … screen record
//  something and then take the audio out of it and ideally clip it … we don't have to display the video"). Pick a video
//  from Photos; its sound shows as bars; drag the two ends to the part you want (it opens on the sound itself, the quiet
//  ends left out); play the part; Use → an .m4a (AAC) with a short fade in and out, at most `ZikrAudio.maxSeconds`.
//  The video is never shown and its temp copy is removed when the sheet goes.
//

import SwiftUI
import PhotosUI
import AVFoundation

/// A video picked in Photos, copied to a temp file we own.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("memo-video-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

/// The sheet's handle on a pick (PhotosPickerItem isn't Identifiable).
struct VideoPick: Identifiable {
    let id = UUID()
    let item: PhotosPickerItem
}

/// Reading a video's sound: its bars, and the clip out of it.
enum VideoSound {
    struct Overview: Sendable { let levels: [Float]; let duration: Double }

    /// Peak levels 0…1 in `count` buckets across the whole sound, and its length; nil when the video has no sound.
    static func overview(of url: URL, count: Int = 90) async -> Overview? {
        await Task.detached(priority: .userInitiated) { () -> Overview? in
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let duration = try? await asset.load(.duration).seconds, duration > 0,
                  let reader = try? AVAssetReader(asset: asset) else { return nil }
            let rate = 8000.0
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1, AVSampleRateKey: rate,
            ])
            reader.add(output)
            guard reader.startReading() else { return nil }
            let perBucket = max(1, Int((duration * rate) / Double(count)))
            var levels: [Float] = []
            var peak: Int16 = 0, inBucket = 0
            while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                                  dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { continue }
                pointer.withMemoryRebound(to: Int16.self, capacity: length / 2) { samples in
                    for i in 0..<(length / 2) {
                        let v = samples[i] == .min ? Int16.max : abs(samples[i])
                        if v > peak { peak = v }
                        inBucket += 1
                        if inBucket == perBucket {
                            levels.append(Float(peak) / Float(Int16.max))
                            peak = 0; inBucket = 0
                        }
                    }
                }
            }
            if inBucket > 0 { levels.append(Float(peak) / Float(Int16.max)) }
            guard !levels.isEmpty, levels.contains(where: { $0 > 0.01 }) else { return nil }
            return Overview(levels: levels, duration: duration)
        }.value
    }

    /// The part that has sound: from the first bar over a sixth of the loudest to the last, a bar of room each side.
    static func soundRange(_ o: Overview) -> ClosedRange<Double> {
        let loudest = o.levels.max() ?? 0
        let threshold = loudest / 6
        let first = o.levels.firstIndex { $0 >= threshold } ?? 0
        let last = o.levels.lastIndex { $0 >= threshold } ?? (o.levels.count - 1)
        let bar = o.duration / Double(o.levels.count)
        return max(0, Double(first - 1) * bar)...min(o.duration, Double(last + 2) * bar)
    }

    /// The clip from `start` to `end` as an AAC .m4a, faded in over 50 ms and out over 0.25 s (no click at a cut).
    static func clip(_ url: URL, from start: Double, to end: Double) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw CocoaError(.fileReadCorruptFile) }
        let scale: CMTimeScale = 600
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: scale),
                                end: CMTime(seconds: end, preferredTimescale: scale))
        // Sound only, so the export never touches the picture.
        let composition = AVMutableComposition()
        guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw CocoaError(.fileWriteUnknown) }
        try audio.insertTimeRange(range, of: track, at: .zero)
        let length = end - start
        let fadeIn = min(0.05, length / 4), fadeOut = min(0.25, length / 4)
        let params = AVMutableAudioMixInputParameters(track: audio)
        params.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
                             timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: fadeIn, preferredTimescale: scale)))
        params.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0,
                             timeRange: CMTimeRange(start: CMTime(seconds: length - fadeOut, preferredTimescale: scale),
                                                    duration: CMTime(seconds: fadeOut, preferredTimescale: scale)))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        else { throw CocoaError(.fileWriteUnknown) }
        session.audioMix = mix
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("memo-clip-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: out) }
        try await session.export(to: out, as: .m4a)
        return try Data(contentsOf: out)
    }
}

/// The clip picker: the video's sound as bars, two ends to drag, play the part, Use.
struct MemoFromVideoSheet: View {
    let pick: VideoPick
    let onUse: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case loading, ready, noSound, failed }
    @State private var phase: Phase = .loading
    @State private var video: URL?
    @State private var overview: VideoSound.Overview?
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var player: AVPlayer?
    @State private var timeObserver: Any?
    @State private var playhead: Double?
    @State private var saving = false

    private var duration: Double { overview?.duration ?? 0 }
    private static let minLength: Double = 0.5

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .noSound:
                    message("This video has no sound.")
                case .failed:
                    message("Couldn't open this video.")
                case .ready:
                    Text("Drag the ends to the part you want")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let overview { trimmer(overview) }
                    times
                    playButton
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Voice memo from a video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Use", action: use).disabled(phase != .ready)
                    }
                }
            }
        }
        .presentationDetents([.height(360)])
        .presentationBackground(Color(.systemBackground))
        .interactiveDismissDisabled(saving)
        .task { await load() }
        .onDisappear(perform: cleanUp)
    }

    private func message(_ words: String) -> some View {
        Text(words)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The bars and the two ends

    private func trimmer(_ o: VideoSound.Overview) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let x = { (t: Double) in CGFloat(t / max(duration, 0.001)) * w }
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 1.5) {
                    ForEach(Array(o.levels.enumerated()), id: \.offset) { i, level in
                        let t = (Double(i) + 0.5) / Double(o.levels.count) * duration
                        Capsule()
                            .fill(t >= start && t <= end ? Color.sage : Color.primary.opacity(0.18))
                            .frame(height: max(3, CGFloat(level) * geo.size.height * 0.9))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: geo.size.height)
                // The chosen part, outlined.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.sage, lineWidth: 2)
                    .frame(width: max(x(end) - x(start), 2), height: geo.size.height)
                    .offset(x: x(start))
                    .allowsHitTesting(false)
                if let playhead {
                    Rectangle().fill(Color.primary.opacity(0.8))
                        .frame(width: 2, height: geo.size.height)
                        .offset(x: x(playhead) - 1)
                        .allowsHitTesting(false)
                }
                handle.offset(x: x(start) - 14)
                    .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged { v in
                        move(start: Double(v.location.x / w) * duration)
                    })
                handle.offset(x: x(end) - 14)
                    .gesture(DragGesture(coordinateSpace: .named("trim")).onChanged { v in
                        move(end: Double(v.location.x / w) * duration)
                    })
            }
            .coordinateSpace(.named("trim"))
        }
        .frame(height: 96)
        .sensoryFeedback(.selection, trigger: Int(start * 4) + Int(end * 4) * 10_000)
    }

    /// A grip on each end, wider than it looks so a thumb finds it.
    private var handle: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.sage)
            .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 18))
            .frame(width: 10, height: 52)
            .frame(width: 28, height: 96)
            .contentShape(Rectangle())
    }

    private func move(start new: Double? = nil, end newEnd: Double? = nil) {
        stop()
        if let new {
            start = min(max(0, new), end - Self.minLength)
            if end - start > ZikrAudio.maxSeconds { end = start + ZikrAudio.maxSeconds }
        }
        if let newEnd {
            end = max(min(duration, newEnd), start + Self.minLength)
            if end - start > ZikrAudio.maxSeconds { start = end - ZikrAudio.maxSeconds }
        }
    }

    private var times: some View {
        HStack {
            Text(clock(start))
            Spacer()
            Text(String(format: "%.1f s", end - start)).foregroundStyle(.primary)
            Spacer()
            Text(clock(end))
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var playButton: some View {
        Button(action: togglePlay) {
            Image(systemName: playhead == nil ? "play.fill" : "stop.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.sage)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.sage.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playhead == nil ? "Play the part" : "Stop")
    }

    private func clock(_ t: Double) -> String {
        let tenths = Int((t * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    // MARK: Loading, playing, using

    private func load() async {
        guard let picked = try? await pick.item.loadTransferable(type: PickedVideo.self) else { phase = .failed; return }
        video = picked.url
        guard let o = await VideoSound.overview(of: picked.url) else { phase = .noSound; return }
        overview = o
        let sound = VideoSound.soundRange(o)
        start = sound.lowerBound
        end = min(sound.upperBound, start + ZikrAudio.maxSeconds)
        if end - start < Self.minLength { start = 0; end = min(o.duration, ZikrAudio.maxSeconds) }
        phase = .ready
    }

    private func togglePlay() {
        if playhead != nil { stop(); return }
        guard let video else { return }
        ZikrAudio.stopAll()
        let p = player ?? AVPlayer(url: video)
        player = p
        Task {
            // Playback even with the ring / silent switch on, set up off the main thread.
            await Task.detached {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
            }.value
            await p.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            playhead = start
            let stopAt = end
            timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { time in
                MainActor.assumeIsolated {
                    guard playhead != nil else { return }
                    if time.seconds >= stopAt { stop() } else { playhead = time.seconds }
                }
            }
            p.play()
        }
    }

    private func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playhead = nil
    }

    private func use() {
        guard let video else { return }
        stop()
        saving = true
        Task {
            do {
                let data = try await VideoSound.clip(video, from: start, to: end)
                onUse(data)
                dismiss()
            } catch {
                print("❌ memo from video: \(error.localizedDescription)")
                saving = false
                phase = .failed
            }
        }
    }

    private func cleanUp() {
        stop()
        player = nil
        if let video { try? FileManager.default.removeItem(at: video) }
    }
}
