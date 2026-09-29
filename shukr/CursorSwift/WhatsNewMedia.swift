//
//  WhatsNewMedia.swift
//  shukr
//
//  What's new v4: the note composer and its media (owner, 2026-09-29: "draw on any images I upload …
//  multi upload photos / vids").
//  - `NoteComposer`: Works / Not yet (on something he asked for) or a comment (any change), words, and
//    any number of photos and videos from the library, plus the camera.
//  - A photo opens in `PhotoMarkupView` (PencilKit + Apple's tool picker); Done saves the drawing as a
//    new photo right after the original, which stays (he can remove either).
//  - Videos are exported to 960×540 H.264, at most 60 s, so a pull off the phone stays quick
//    (a 30 s 4K clip is 100+ MB).
//

import SwiftUI
import PhotosUI
import PencilKit
import AVKit
import UniformTypeIdentifiers

// MARK: - Composer

struct NoteComposer: View {
    let entry: WhatsNewEntry
    /// Answering this ask (Works / Not yet); nil = a comment on the change.
    let ask: WhatsNewAsk?
    var startKind: FeedbackItem.Kind = .issue
    /// Editing something already said (not picked up yet).
    var existing: FeedbackItem? = nil
    var onDone: (FeedbackItem?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = FeedbackStore.shared
    @State private var kind: FeedbackItem.Kind = .issue
    @State private var text = ""
    @State private var media: [String] = []
    /// Added in this composer (removed again on Cancel).
    @State private var added: [String] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var loading = 0
    @State private var showCamera = false
    @State private var marking: MarkupTarget?
    @State private var playing: PlayTarget?
    @State private var notice: String?
    @State private var confirmDiscard = false
    @FocusState private var typing: Bool

    private var isAnswer: Bool { ask != nil }
    private var changed: Bool {
        guard let e = existing else { return isAnswer || !text.trimmingCharacters(in: .whitespaces).isEmpty || !media.isEmpty }
        return e.kind != kind || e.text != text.trimmingCharacters(in: .whitespacesAndNewlines) || e.attachments != media
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    context
                    if isAnswer {
                        Picker("Answer", selection: $kind) {
                            Text("Works").tag(FeedbackItem.Kind.works)
                            Text("Not yet").tag(FeedbackItem.Kind.issue)
                        }
                        .pickerStyle(.segmented)
                        .sensoryFeedback(.selection, trigger: kind)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isAnswer && kind == .works ? "Anything to add? (optional)" : isAnswer ? "What's off? (optional)" : "Your comment")
                            .font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
                        TextField("Say it however you like", text: $text, axis: .vertical)
                            .lineLimit(3...10)
                            .focused($typing)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    }
                    mediaSection
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .fontDesign(.rounded)
            .navigationTitle(isAnswer ? "Your answer" : "Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if added.isEmpty && !changedWords { cancel() } else { confirmDiscard = true } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!changed || loading > 0 || (!isAnswer && text.trimmingCharacters(in: .whitespaces).isEmpty && media.isEmpty))
                }
            }
            .confirmationDialog("Discard this?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { cancel() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(changed)
        .onAppear {
            if let e = existing { kind = e.kind; text = e.text; media = e.attachments }
            else { kind = isAnswer ? startKind : .note }
            if kind == .issue || kind == .note { typing = true }
        }
        .onChange(of: picks) { _, list in
            guard !list.isEmpty else { return }
            typing = false
            let batch = list
            picks = []
            Task { await load(batch) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task {
                    loading += 1
                    if let data = await downscaledJPEG(image, maxSide: 1600), let name = store.storeMedia(data, ext: "jpg") { append(name) }
                    loading -= 1
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $marking) { target in
            PhotoMarkupView(name: target.name) { data in
                guard let data, let name = store.storeMedia(data, ext: "jpg") else { return }
                // The drawn copy goes right after the original, which stays.
                if let i = media.firstIndex(of: target.name) { media.insert(name, at: i + 1) } else { media.append(name) }
                added.append(name)
            }
        }
        .sheet(item: $playing) { target in
            if let url = store.mediaURL(target.name) {
                VideoPlayer(player: AVPlayer(url: url)).ignoresSafeArea()
            }
        }
    }

    private var changedWords: Bool { (existing?.text ?? "") != text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var context: some View {
        HStack(spacing: 12) {
            if let shot = entry.shots?.first { ShotThumb(name: shot, size: 48) }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.short).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("\(WhatsNew.area(entry.topic)) · \(WhatsNew.whenLabel(entry.when))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(media.isEmpty ? "Photos and videos" : "Photos and videos · \(media.count)")
                if loading > 0 { ProgressView().controlSize(.mini).padding(.leading, 4) }
            }
            .font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
            if !media.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(media, id: \.self) { name in tile(name) }
                }
            }
            HStack(spacing: 8) {
                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                    Label("Photos & videos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { typing = false; showCamera = true } label: {
                        Label("Camera", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.sage)
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            Text(notice ?? "Tap a photo to draw on it; the original is kept too. Videos keep their first minute.")
                .font(.caption).foregroundStyle(notice == nil ? .secondary : Color.orange).padding(.leading, 4)
        }
    }

    private func tile(_ name: String) -> some View {
        let video = FeedbackStore.isVideo(name)
        return MediaThumb(name: name)
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .center) {
                if video {
                    Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                        .padding(10).background(Circle().fill(.black.opacity(0.35)))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !video {
                    Image(systemName: "pencil.tip").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(5).background(Circle().fill(.black.opacity(0.45))).padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.snappy) { media.removeAll { $0 == name } }
                } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(.black.opacity(0.55)))
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                }
                .buttonStyle(.plain)
                .padding(2)
                .accessibilityLabel("Remove")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                typing = false
                if video { playing = PlayTarget(name: name) } else { marking = MarkupTarget(name: name) }
            }
            .accessibilityLabel(video ? "Video, tap to play" : "Photo, tap to draw on it")
    }

    private func append(_ name: String) {
        withAnimation(.snappy) { media.append(name) }
        added.append(name)
    }

    private func load(_ batch: [PhotosPickerItem]) async {
        for item in batch {
            loading += 1
            defer { loading -= 1 }
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { continue }
                do {
                    let (out, trimmed) = try await exportVideo(movie.url)
                    if let name = store.storeMedia(file: out, ext: "mp4") { append(name) }
                    if trimmed { notice = "A video was longer than a minute: it keeps its first minute." }
                } catch {
                    notice = "Couldn't add a video (\(error.localizedDescription))."
                }
                try? FileManager.default.removeItem(at: movie.url)
            } else if let data = try? await item.loadTransferable(type: Data.self),
                      let small = await downscaledJPEG(data, maxSide: 1600),
                      let name = store.storeMedia(small, ext: "jpg") {
                append(name)
            }
        }
    }

    private func save() {
        typing = false
        // Files dropped from the list during this edit that were added here: gone for good.
        store.discardMedia(added.filter { !media.contains($0) })
        let item = store.save(existing: existing, entry: entry, ask: ask?.id, kind: kind, text: text, media: media)
        triggerSomeVibration(type: .success)
        onDone(item)
        dismiss()
    }

    private func cancel() {
        store.discardMedia(added)
        onDone(nil)
        dismiss()
    }

    private struct MarkupTarget: Identifiable { let name: String; var id: String { name } }
    private struct PlayTarget: Identifiable { let name: String; var id: String { name } }
}

// MARK: - Thumbnails

/// A stored photo / video's square thumbnail, made off the main thread.
struct MediaThumb: View {
    let name: String
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .task(id: name) {
                guard let url = FeedbackStore.shared.mediaURL(name) else { return }
                let video = FeedbackStore.isVideo(name)
                image = await Task.detached(priority: .utility) { () -> UIImage? in
                    if video {
                        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                        gen.appliesPreferredTrackTransform = true
                        gen.maximumSize = CGSize(width: 300, height: 300)
                        return (try? await gen.image(at: .zero)).map { UIImage(cgImage: $0.image) }
                    }
                    guard let data = try? Data(contentsOf: url), let small = jpegThumbnail(data, maxSide: 300) else { return nil }
                    return UIImage(data: small)
                }.value
            }
    }
}

/// A bundled screenshot's thumbnail (What's new's own pictures), decoded off the main thread.
struct ShotThumb: View {
    let name: String
    var size: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .task(id: name) {
                let name = name, px = size * 3
                image = await Task.detached(priority: .utility) {
                    guard let full = WhatsNew.image(name), full.size.width > 0, full.size.height > 0 else { return nil }
                    let scale = px / min(full.size.width, full.size.height)
                    return full.preparingThumbnail(of: CGSize(width: full.size.width * scale, height: full.size.height * scale))
                }.value
            }
    }
}

// MARK: - Videos

/// A picked video, copied out of the picker's temporary file.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("pick-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

enum VideoExportError: LocalizedError {
    case cantExport
    var errorDescription: String? { "the video couldn't be converted" }
}

/// 960×540 H.264 MP4, the first 60 s at most. Returns the file and whether it was trimmed.
func exportVideo(_ url: URL) async throws -> (URL, Bool) {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    let limit = CMTime(seconds: 60, preferredTimescale: 600)
    guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset960x540) else { throw VideoExportError.cantExport }
    let out = FileManager.default.temporaryDirectory.appendingPathComponent("note-\(UUID().uuidString).mp4")
    let trimmed = duration > limit
    if trimmed { session.timeRange = CMTimeRange(start: .zero, duration: limit) }
    session.shouldOptimizeForNetworkUse = true
    try await session.export(to: out, as: .mp4)
    return (out, trimmed)
}

// MARK: - Drawing on a photo

/// Full screen: the photo with a PencilKit canvas over exactly its frame and Apple's tool picker.
/// Done hands back the photo with the drawing baked in (JPEG), or nil on Cancel.
struct PhotoMarkupView: View {
    let name: String
    let onDone: (Data?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var model = MarkupModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    GeometryReader { geo in
                        let fit = fitted(image.size, in: geo.size)
                        ZStack {
                            Image(uiImage: image).resizable().scaledToFit()
                            MarkupCanvas(model: model)
                        }
                        .frame(width: fit.width, height: fit.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .onAppear { model.size = fit }
                        .onChange(of: geo.size) { _, s in model.size = fitted(image.size, in: s) }
                    }
                    .padding(.bottom, 90)       // room for the tool picker
                } else {
                    ProgressView().tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone(nil); dismiss() }.foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }.fontWeight(.semibold).disabled(image == nil)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            guard let url = FeedbackStore.shared.mediaURL(name) else { return }
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path)?.preparingForDisplay() }.value
        }
    }

    private func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let s = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * s, height: size.height * s)
    }

    private func finish() {
        guard let image, model.size.width > 0 else { dismiss(); return }
        let drawing = model.canvas.drawing
        guard !drawing.strokes.isEmpty else { onDone(nil); dismiss(); return }
        let scale = image.size.width / model.size.width
        let ink = drawing.image(from: CGRect(origin: .zero, size: model.size), scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rect = CGRect(origin: .zero, size: image.size)
        let composed = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: rect)
            ink.draw(in: rect)
        }
        onDone(composed.jpegData(compressionQuality: 0.85))
        dismiss()
    }
}

@Observable final class MarkupModel {
    let canvas = PKCanvasView()
    let picker = PKToolPicker()
    var size: CGSize = .zero
}

private struct MarkupCanvas: UIViewRepresentable {
    let model: MarkupModel
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = model.canvas
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput            // a finger draws
        let red = PKInkingTool(.pen, color: .systemRed, width: 6)    // red stands out on a screenshot
        canvas.tool = red
        model.picker.selectedTool = red
        model.picker.setVisible(true, forFirstResponder: canvas)
        model.picker.addObserver(canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {}
}
