//
//  PrayerTimeEditSheet.swift
//  shukr
//
//  Long-press a completed prayer → "when did you pray?" (Design's direction A, owner 2026-10-19: "this my favorite by far";
//  spec board/mocks/prayer-editor/spec.md). The map sheet's header (the name in light type over one quiet line, round ✕ and
//  ✓ on the right), the prayer's window as a ring with the marked dot you drag round it, a small time wheel and the score
//  inside the ring, then one flat card: Where · Photo · Note. ✓ shows only when the time, the place or the note changed;
//  photos save at once. No swipe to dismiss: ✕ with an unsaved edit asks first ("A").
//

import SwiftUI
import MapKit

struct PrayerTimeEditSheet: View {
    let prayer: PrayerModel
    /// The day's earliest and latest time it can be marked at: from the prayer's start (never earlier) to now or the next
    /// Fajr (the day's rollover), whichever is first. After the window it's Qaza, e.g. Isha at 12:30 AM.
    let range: ClosedRange<Date>
    /// Every box saves itself (owner, 2026-10-19: "stay away from the check mark altogether and just fix the time so that it
    /// just always saves"): the row behind applies each one (or holds it for the day page until the sheet is gone).
    var onTime: (Date) -> Void
    var onRevertTime: () -> Void
    var onSpot: (CLLocationCoordinate2D) -> Void
    var onRevertSpot: () -> Void
    var onClose: () -> Void
    /// Where it was prayed: the map box opens `PrayerLocationPicker`. Off when the sheet is opened from the prayer map, which
    /// moves pins on the map itself.
    var showsLocation = true

    /// The time on the dot and the wheel; `saved` what's in the model (or held for it). A release on a valid, different
    /// time saves it; an invalid one springs back to `saved`.
    @State private var draft: Date
    @State private var saved: Date
    /// What the app recorded, for the ↺ (the prayer's own recorded time / spot, else what it opened with).
    private let recordedTime: Date
    @State private var spot: CLLocationCoordinate2D?
    private let recordedSpot: CLLocationCoordinate2D?
    @State private var spotName: String?
    @State private var pickingSpot = false

    /// The prayer's photo (PrayerPhotos.swift): added or retaken while the prayer's window is on and it's marked (owner:
    /// "they can add photos any time in that window so long as its marked"), seen any time after. Saved at once.
    @State private var photoTarget: PrayerPhotoTarget?
    @State private var askPhoto = false
    @State private var photoSaved = false
    /// Removed, but the file waits ~4 s for Undo (it goes for good then, or when the sheet closes).
    @State private var removing: Task<Void, Never>?
    private var photoKey: String { PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name) }
    private var photoInWindow: Bool { prayer.isCompleted && Date() < prayer.endTime }

    /// The note (the photos' note file, PrayerPhotos.note — the day page and Journey read it): saved on the keyboard's Done
    /// and on close.
    @State private var draftNote = ""
    @State private var savedNote = ""
    @State private var noteSaved = false
    /// The note box grown to full width (its field focuses once it's there).
    @State private var writingNote = false
    @FocusState private var noteFocused: Bool

    @State private var contentHeight: CGFloat = 0
    @State private var detent: PresentationDetent = .large
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    init(prayer: PrayerModel, range: ClosedRange<Date>, showsLocation: Bool = true,
         onTime: @escaping (Date) -> Void, onRevertTime: @escaping () -> Void,
         onSpot: @escaping (CLLocationCoordinate2D) -> Void, onRevertSpot: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.prayer = prayer
        self.range = range
        self.showsLocation = showsLocation
        self.onTime = onTime
        self.onRevertTime = onRevertTime
        self.onSpot = onSpot
        self.onRevertSpot = onRevertSpot
        self.onClose = onClose
        // Open on the time saved for this prayer (owner, 2026-09-26), kept within what can be saved.
        let marked = prayer.timeAtComplete ?? range.lowerBound
        let start = min(max(marked, range.lowerBound), range.upperBound)
        self._draft = State(initialValue: start)
        self._saved = State(initialValue: start)
        self.recordedTime = prayer.recordedTimeAtComplete ?? marked
        let here = prayer.latPrayedAt.flatMap { lat in prayer.longPrayedAt.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
        self._spot = State(initialValue: here)
        self.recordedSpot = prayer.recordedSpot ?? here
        let note = PrayerPhotos.note(PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name)) ?? ""
        self._draftNote = State(initialValue: note)
        self._savedNote = State(initialValue: note)
    }

    /// The ↺s: edited from how it was marked (they stay until tapped, across reopens — the model keeps the recorded ones).
    private var timeEdited: Bool { abs(saved.timeIntervalSince(recordedTime)) >= 30 }
    private var spotEdited: Bool {
        guard let spot, let recordedSpot else { return false }
        return CLLocation(latitude: spot.latitude, longitude: spot.longitude)
            .distance(from: CLLocation(latitude: recordedSpot.latitude, longitude: recordedSpot.longitude)) > 3
    }

    /// The tour's fix step is in this sheet: its tip continues here (audit J: "nothing goes silent"). The step is the time
    /// alone (owner: only the intended thing): the ring box only.
    private var tourTip: Bool { TourRuntime.shared.step == .list && TourRuntime.isPracticeAnywhere(prayer) }
    private var shift: TimeInterval { PracticeClock.shift(for: prayer) }
    private func inYellow(_ t: Date) -> Bool {
        PrayerScoring.grade(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: t)) == .onTime
    }

    private var subtitle: String {
        "\(shortTimePM(prayer.startTime.addingTimeInterval(shift))) – \(shortTimePM(prayer.endTime.addingTimeInterval(shift))) · when did you pray?"
    }

    var body: some View {
        VStack(spacing: 14) {
            // The tour's words for this step are in its panel, over the sheet (TourEditorPanelWindow).
            MapSheetHeader(title: prayer.displayName, subtitle: subtitle) {
                MapSheetCircleButton(symbol: "xmark", label: "Close") { close() }
            }
            .padding(.top, 20)
            .padding(.horizontal, 4)

            if writingNote {
                noteEditor
            } else if tourTip {
                ringBox(size: 240)
            } else if typeSize.isAccessibilitySize {
                // Large text can't fit the grid: the boxes stacked, the ring at its full size.
                VStack(spacing: 8) {
                    ringBox(size: 240)
                    noteBox.frame(minHeight: 62)
                    HStack(spacing: 8) { mapBox; photoBox }.frame(height: 150)
                }
            } else {
                grid
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)   // the home bar's own inset is under it (Design saw ~50 pt spare at 16 + 8)
        .fontDesign(.rounded)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        // The Liquid Glass sheet (owner, 2026-10-19: "should we be using the translucent sheet, like the liquid glass sheet that
        // we use in a lot of other places in the app?"): nothing painted on iOS 26, a material before; the boxes keep their fill.
        .modifier(EditorSheetGlass())
        .onAppear { if tourTip { TourEditorPanelWindow.show() } }
        .onDisappear {
            TourEditorPanelWindow.hide()
            finishRemoving()
            if draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != savedNote { commitNote() }
        }
        .onChange(of: draft, initial: true) { _, now in
            guard tourTip else { return }
            TourRuntime.shared.editorInYellow = inYellow(now)
            TourRuntime.shared.editorScore = PrayerScoring.points(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: now))
        }
        // Writing a note needs the keyboard's room: the sheet goes full height while the field is up.
        .onChange(of: writingNote) { _, on in withAnimation(.smooth(duration: 0.3)) { detent = on ? .large : fitted } }
        .onChange(of: contentHeight) { _, _ in if !writingNote { detent = fitted } }
        // The keyboard went away some other way: the note is done.
        .onChange(of: noteFocused) { was, now in if was && !now && writingNote { finishNote() } }
        .sheet(isPresented: $pickingSpot) {
            PrayerLocationPicker(prayerName: prayer.displayName, original: spot,
                                 recorded: recordedSpot,
                                 onCancel: { pickingSpot = false },
                                 onPick: { picked in
                                     pickingSpot = false
                                     spot = picked
                                     onSpot(picked)
                                     triggerSomeVibration(type: .soft)
                                 })
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
        .task(id: spot.map { "\($0.latitude),\($0.longitude)" }) {
            spotName = nil
            if prayer.atMasjid, !spotEdited, let masjid = prayer.mosqueName { spotName = masjid; return }
            if let spot { spotName = await PrayerPlaceNames.named(spot) }
        }
        .fullScreenCover(item: $photoTarget, onDismiss: { flash($photoSaved) }) { target in
            PrayerPhotoCapture(target: target) { photoTarget = nil }
        }
        .confirmationDialog("Your photo", isPresented: $askPhoto, titleVisibility: .hidden) {
            Button("Retake") { photoTarget = PrayerPhotoTarget.forMarked(prayer) }
            Button("Remove", role: .destructive) { startRemoving() }
        }
        // The tour's tip at the largest text: the full height.
        .presentationDetents(tourTip && typeSize.isAccessibilitySize ? [.large] : [fitted, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .presentationCornerRadius(28)
    }

    /// The sheet fitted to what it holds.
    private var fitted: PresentationDetent { contentHeight > 0 ? .height(min(contentHeight, 760)) : .large }

    /// Nothing ever waits (every box saved itself), so ✕ just closes.
    private func close() { onClose() }

    // MARK: Saving

    /// A finger lifted off the dot, or the wheel came to rest: a valid, different time saves (once — the scores, the streak
    /// and the Live Activity plan recount then, never per tick); an invalid one springs back to the saved time.
    private func release() {
        guard range.contains(draft) else {
            // The reason shows in the ring long enough to read, then the last saved time comes back.
            let wrong = draft
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                if draft == wrong { withAnimation(.smooth(duration: 0.35)) { draft = saved } }
            }
            return
        }
        let needsYellow = TourRuntime.shared.needsYellow(prayer)
        guard abs(draft.timeIntervalSince(saved)) >= 30 else { return }
        if needsYellow && !inYellow(draft) { return }   // the tour's Fajr fix saves only a yellow time
        saved = draft
        onTime(draft)
        triggerSomeVibration(type: .soft)
        if tourTip {
            // The tour's fix step completes on the release that lands its time, as ✓ did — and the sheet goes, as it did.
            TourRuntime.shared.event(.editorSaved(prayer.name))
            onClose()
        }
    }

    private func revertTime() {
        triggerSomeVibration(type: .light)
        let back = min(max(recordedTime, range.lowerBound), range.upperBound)
        withAnimation(.smooth(duration: 0.35)) { draft = back }
        saved = back
        onRevertTime()
    }

    private func revertSpot() {
        triggerSomeVibration(type: .light)
        spot = recordedSpot
        onRevertSpot()
    }

    private func commitNote() {
        PrayerPhotos.setNote(photoKey, draftNote)
        savedNote = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        draftNote = savedNote
    }

    private func flash(_ flag: Binding<Bool>) {
        withAnimation(.easeOut(duration: 0.2)) { flag.wrappedValue = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { flag.wrappedValue = false }
        }
    }

    /// Remove: the box says "Photo deleted" with Undo for ~4 s; the file goes after that (or when the sheet closes).
    private func startRemoving() {
        removing?.cancel()
        let key = photoKey
        withAnimation(.easeOut(duration: 0.2)) {
            removing = Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                PrayerPhotos.delete(key)
                withAnimation(.easeOut(duration: 0.2)) { removing = nil }
            }
        }
    }
    private func undoRemoving() {
        removing?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { removing = nil }
    }
    private func finishRemoving() {
        guard let task = removing else { return }
        task.cancel()
        PrayerPhotos.delete(photoKey)
        removing = nil
    }

    // MARK: The grid (N2: owner 2026-10-19, "i love n2"; round 2, "more rectangular than it is square")

    @State private var gridWidth: CGFloat = 370
    private static let gap: CGFloat = 8
    private static let lowRow: CGFloat = 90
    private var side: CGFloat { max((gridWidth - Self.gap) / 2, 120) }

    /// Grid A: two equal squares on top, the ring box | the photo box; under them the map | the note, side by side.
    private var grid: some View {
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                ringBox(size: side - 12).frame(width: side, height: side)
                photoBox.frame(width: side, height: side)
            }
            HStack(spacing: Self.gap) {
                if showsLocation { mapBox }
                noteBox
            }
            .frame(height: Self.lowRow)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private func card<Content: View>(radius: CGFloat = 22, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The ↺: "edited, tap to go back to how it was marked" — an icon only (owner, 2026-10-19: "let's just make it an undo
    /// symbol. no other data for it just to save space"), sitting on its box so nothing moves when it comes and goes.
    private func undoChip(onGlass: Bool, label: String, action: @escaping () -> Void) -> some View {
        // One look for both (owner, 2026-10-19: "in the mockups you used diff colors for undo. keep it the same. grayish one
        // you used"): a white ↺ on the map labels' grey glass, never sage.
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background {
                    Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                        .overlay(Circle().fill(Color.black.opacity(0.35)))
                }
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func ringBox(size: CGFloat) -> some View {
        card {
            PrayerTimeEditor(prayer: prayer, draft: $draft, range: range, ringSize: size, boxed: true, onRelease: release)
        }
        .overlay(alignment: .topLeading) {
            if timeEdited && !tourTip {
                undoChip(onGlass: false, label: "Undo edited time, back to \(shortTimePM(recordedTime.addingTimeInterval(shift)))",
                         action: revertTime)
                    .padding(10)
            }
        }
        .animation(.snappy(duration: 0.22), value: timeEdited)
    }

    private var noteBox: some View {
        card(radius: 18) {
            Button { withAnimation(.smooth(duration: 0.25)) { writingNote = true } } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.quote").font(.footnote).foregroundStyle(.secondary).padding(.top, 2)
                    Text(savedNote.isEmpty ? "Add a note" : savedNote)
                        .font(.subheadline)
                        .foregroundStyle(savedNote.isEmpty ? .secondary : .primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .topTrailing) {
            if noteSaved {
                Text("Saved").font(.caption2.weight(.medium)).foregroundStyle(Color.sage).padding(8).transition(.opacity)
            }
        }
    }

    /// Writing a note: the note grows to full width above the keyboard; the keyboard's Done saves it and brings the grid back.
    private var noteEditor: some View {
        TextField("Add a note", text: $draftNote, axis: .vertical)
            .font(.body)
            .lineLimit(3...6)
            .focused($noteFocused)
            .submitLabel(.done)
            .onChange(of: draftNote) { _, text in
                // A vertical field takes Return as a new line: Done is the end of the note.
                if text.contains("\n") {
                    draftNote = text.replacingOccurrences(of: "\n", with: "")
                    finishNote()
                }
            }
            .onSubmit(finishNote)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .onAppear { DispatchQueue.main.async { noteFocused = true } }
    }

    private func finishNote() {
        guard writingNote else { return }
        let changed = draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != savedNote
        if changed { commitNote() }
        noteFocused = false
        withAnimation(.smooth(duration: 0.25)) { writingNote = false }
        if changed { flash($noteSaved) }
    }

    /// The saved spot as a map (MKMapSnapshotter), the place's name on a glass label; tap = Move.
    private var mapBox: some View {
        Button { pickingSpot = true } label: {
            card {
                if let spot {
                    PrayerSpotSnapshot(spot: spot, dark: scheme == .dark)
                        .overlay(alignment: .bottomLeading) {
                            if let spotName {
                                Text(spotName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                                    .padding(8)
                                    .transition(.opacity)
                            }
                        }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse").font(.title3).foregroundStyle(.secondary)
                        Text("No place saved").font(.footnote)
                        Text("Add ›").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topLeading) {
            if spotEdited {
                undoChip(onGlass: true, label: "Undo moved place, back to where you marked", action: revertSpot).padding(8)
            }
        }
        .animation(.snappy(duration: 0.22), value: spotEdited)
        .accessibilityLabel(spot == nil ? "Add where you prayed" : "Where you prayed: \(spotName ?? "on the map"). Move it")
    }

    /// The photo itself, its time on a glass label; empty, a camera and "Add a photo"; after the window, dimmed.
    @ViewBuilder private var photoBox: some View {
        let _ = PrayerPhotoRevision.shared.value
        let has = PrayerPhotos.has(photoKey) && removing == nil
        if removing != nil {
            card {
                VStack(spacing: 6) {
                    Text("Photo deleted").font(.footnote)
                    Button("Undo", action: undoRemoving).font(.footnote.weight(.semibold)).foregroundStyle(Color.sage)
                }
            }
        } else if has {
            // The photo sits in its box (owner, 2026-10-19: "prayer photos should still look like they're in a box. not just
            // take up the box"): the day page's rounded square with the front camera's inset, its time a grey line under it.
            card {
                GeometryReader { geo in
                    let w = max(min(geo.size.width, geo.size.height - 18) - 28, 40)
                    VStack(spacing: 6) {
                        PrayerPhotoCard(key: photoKey, width: w, opens: !photoInWindow)
                        Text(photoSaved ? "Saved" : takenLine)
                            .font(.caption2).foregroundStyle(photoSaved ? Color.sage : .secondary)
                            .contentTransition(.opacity)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .overlay {
                if photoInWindow {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { triggerSomeVibration(type: .light); askPhoto = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Your photo. Retake or remove")
                }
            }
        } else {
            Button {
                triggerSomeVibration(type: .light)
                photoTarget = PrayerPhotoTarget.forMarked(prayer)
            } label: {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "camera").font(.title3).foregroundStyle(.secondary)
                            Text(photoInWindow ? "Add a photo" : "No photo").font(.footnote)
                            Text(photoInWindow ? "While \(prayer.displayName) is on" : "Only while \(prayer.displayName) is on")
                                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!photoInWindow)
            .opacity(photoInWindow ? 1 : 0.55)
        }
    }

    /// "6:58 PM": the photo file's own time.
    private var takenLine: String {
        let url = PrayerPhotos.url(photoKey, front: false)
        let at = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
        return at.map { shortTimePM($0) } ?? "Your photo"
    }
}

/// The saved spot as a still map (MKMapSnapshotter, the dark style in dark mode), the pin in the middle.
struct PrayerSpotSnapshot: View {
    let spot: CLLocationCoordinate2D
    let dark: Bool
    @State private var image: UIImage?
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 22))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.sage)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .task(id: "\(spot.latitude),\(spot.longitude),\(dark),\(Int(size.width))x\(Int(size.height))") {
            guard size.width > 1 else { return }
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: spot, latitudinalMeters: 450, longitudinalMeters: 450)
            options.size = size
            options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            options.pointOfInterestFilter = .excludingAll
            let shot = try? await MKMapSnapshotter(options: options).start()
            withAnimation(.easeOut(duration: 0.2)) { image = shot?.image }
        }
    }
}

/// The heart of editing a prayer's time: the prayer's window as a ring with the marked dot you drag round it, a small time
/// wheel and the score inside it, the recorded time to go back to, and why an impossible time can't be saved. Used by the
/// time editor sheet and inline on the map's prayer page.
struct PrayerTimeEditor: View {
    let prayer: PrayerModel
    @Binding var draft: Date
    /// From the prayer's start to now or the next Fajr (the day's rollover).
    let range: ClosedRange<Date>
    /// The score inside the ring (the map's prayer page shows the score in its header instead).
    var showsScore = true
    /// The ring's size (the editor sheet's bento box draws it at 188 pt).
    var ringSize: CGFloat = PrayerWindowRing.size
    /// In the sheet's ring box (N2): nothing under the ring — an impossible time says why in the score's slot, and the ↺ on
    /// the box replaces "You marked it at … · use that".
    var boxed = false
    /// A finger lifted off the dot, or the wheel came to rest: the sheet saves then (never per tick).
    var onRelease: () -> Void = {}

    var isValid: Bool { range.contains(draft) }
    /// The tour's practice clock (0 for a real prayer).
    private var shift: TimeInterval { PracticeClock.shift(for: prayer) }
    /// A Jumu'ah isn't graded by the clock (full marks, "Jumu'ah"), so the editor agrees with Save.
    private var score: Double {
        prayer.isJumuah ? 1 : PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)
    }

    /// The dot dragged round the ring: that point of the window, to the minute, kept within what can be saved and never past
    /// the window's end (a Qaza is picked on the wheel).
    private func pickFromRing(_ fraction: Double) {
        let window = prayer.endTime.timeIntervalSince(prayer.startTime)
        let raw = prayer.startTime.addingTimeInterval(window * fraction)
        let minute = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded() * 60)
        let upper = min(range.upperBound, prayer.endTime)
        let picked = min(max(minute, range.lowerBound), max(upper, range.lowerBound))
        if picked != draft { draft = picked }
    }

    /// AM / PM only when the editable range crosses noon or midnight (a Qaza late at night).
    private var showsMeridiem: Bool {
        let cal = Calendar.current
        let a = range.lowerBound.addingTimeInterval(shift), b = range.upperBound.addingTimeInterval(shift)
        return !cal.isDate(a, inSameDayAs: b) || (cal.component(.hour, from: a) < 12) != (cal.component(.hour, from: b) < 12)
    }

    /// Why an out-of-range time can't be saved, in one short line (it shares the date line's slot, so the sheet never grows —
    /// owner, 2026-10-19: "the view shifts"): nearer (on the clock) to the start → it's before the prayer; nearer the other
    /// end → it hasn't happened yet, or it's past the day's rollover.
    private var invalidReason: String {
        let cal = Calendar.current
        func clock(_ d: Date) -> Double {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        func dist(_ a: Date, _ b: Date) -> Double { let x = abs(clock(a) - clock(b)); return min(x, 1440 - x) }
        if dist(draft, range.lowerBound) <= dist(draft, range.upperBound) {
            return "Before \(prayer.name) began at \(shortTimePM(range.lowerBound.addingTimeInterval(shift)))."
        }
        // The upper bound is now unless the day already rolled over before now.
        if range.upperBound < Date().addingTimeInterval(-60) {
            return "After Fajr at \(shortTimePM(range.upperBound.addingTimeInterval(shift))), the next day."
        }
        return "Not yet. It's \(shortTimePM(range.upperBound.addingTimeInterval(shift))) now."
    }

    var body: some View {
        let grade = PrayerScoring.grade(for: score)
        VStack(spacing: 12) {
            ZStack {
                PrayerWindowRing(start: prayer.startTime, end: prayer.endTime, marked: draft, valid: isValid,
                                 size: ringSize, onPick: pickFromRing, onRelease: onRelease)
                VStack(spacing: 2) {
                    // The tour's practice prayer reads on its plain clock (PracticeClock): the wheel shows, and picks,
                    // shifted times.
                    // The wheel sets it only when it comes to rest (didSelectRow): that's the release.
                    PrayerTimeWheel(time: Binding(get: { draft.addingTimeInterval(shift) },
                                                  set: { draft = $0.addingTimeInterval(-shift); onRelease() }),
                                    day: prayer.startTime.addingTimeInterval(shift),
                                    range: range.lowerBound.addingTimeInterval(shift)...range.upperBound.addingTimeInterval(shift),
                                    compact: true, meridiem: showsMeridiem)
                        .frame(width: min(showsMeridiem ? 132 : 92, ringSize * 0.7), height: boxed ? 84 : 110)
                        // The wheel keeps to its box (UIPickerView draws past it), its rows fading out top and bottom.
                        .clipped()
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28),
                                                     .init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                    if boxed && !isValid {
                        // Why it can't be saved, in the score's slot (let go and it springs back to the saved time).
                        Text(invalidReason)
                            .font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                            .frame(width: ringSize * 0.62, height: 30)
                            .transition(.opacity)
                    } else if showsScore {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(isValid ? "\(PrayerScoring.points(for: score))" : "–")
                                .font(.system(size: 20, weight: .light, design: .rounded))
                                .contentTransition(.numericText(value: score))
                            Text(isValid ? (prayer.isJumuah ? "Jumu'ah" : grade.rawValue) : "not a valid time")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(isValid ? PrayerScoring.color(for: score) : .secondary)
                                .contentTransition(.opacity)
                        }
                        .animation(.snappy, value: score)
                    }
                }
                // The score sits just under the wheel, so the ring can stay small (owner, 2026-10-19: "make the circle a
                // little smaller by moving the score line inside just a tad higher").
                .offset(y: showsScore ? 4 : 0)
            }
            .frame(width: ringSize, height: ringSize)
            .frame(maxWidth: .infinity)

            if !boxed { underRing }
        }
        .sensoryFeedback(.selection, trigger: grade)
    }

    /// Under the ring, outside the bento (the map's prayer page): the recorded time to go back to, and one line kept for the
    /// date or the reason.
    @ViewBuilder private var underRing: some View {
            // Edited before: what the app recorded, one tap to go back to it.
            if let recorded = prayer.recordedTimeAtComplete, abs(draft.timeIntervalSince(recorded)) >= 30 {
                Button {
                    draft = min(max(recorded, range.lowerBound), range.upperBound)
                } label: {
                    Label("You marked it at \(shortTimePM(recorded.addingTimeInterval(shift))) · use that", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            // One line under the ring, always there so the card below never moves (owner, 2026-10-19: "ideally it doesn't
            // shift the layout"; "the view shifts"): out of range, why it can't be saved (✓ stays away until then); on
            // another calendar day than the prayer's window (a Fajr made up the next morning), that day's date — the time
            // is in the wheel; otherwise empty, its height kept.
            let otherDay = !Calendar.current.isDate(draft, inSameDayAs: prayer.startTime)
            Text(isValid ? draft.addingTimeInterval(shift).formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                         : invalidReason)
                .font(.footnote)
                .fontWeight(.light)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .opacity(!isValid || otherDay ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: !isValid || otherDay)
                .accessibilityHidden(isValid && !otherDay)
    }
}

/// The prayer's window as a ring (as PrayerGoalDial draws a window, Design's direction A): clockwise from the top, green the
/// first 30 minutes, yellow to the window's middle plus 15, red to the end (PrayerScoring), small gaps between them, each
/// lit up to the marked dot. The dot is the marked ring's hollow one; drag it round the window to move the time. Past the
/// end (a Qaza, picked on the wheel) the whole ring is lit and the dot rests at the end, grey.
struct PrayerWindowRing: View {
    let start: Date
    let end: Date
    let marked: Date
    var valid = true
    var size: CGFloat = Self.size
    /// The finger on the ring: the fraction of the window under it, 0…1 (never past the end).
    var onPick: (Double) -> Void = { _ in }
    /// The finger lifted after moving the dot.
    var onRelease: () -> Void = {}
    @Environment(\.circleTheme) private var theme
    @State private var dragging = false

    static let size: CGFloat = 240
    static let radius: CGFloat = 98
    private static let gap = 2.4

    private var zones: [(from: Double, to: Double, score: Double)] {
        let total = max(end.timeIntervalSince(start), 1)
        let early = min(PrayerScoring.earlyWindow / total, 1)
        let mid = early + (1 - early) / 2
        return early >= 1 ? [(0, 360, 1)] : [(0, early * 360, 1), (early * 360, mid * 360, 0.9), (mid * 360, 360, 0.7)]
    }
    private var isQaza: Bool { marked > end }
    private var angle: Double {
        let total = max(end.timeIntervalSince(start), 1)
        return min(max(marked.timeIntervalSince(start) / total, 0), 1) * 360
    }
    private var dotColor: Color {
        guard valid else { return Color(.tertiaryLabel) }
        if isQaza { return PrayerScoring.color(for: PrayerScoring.qaza) }
        return PrayerScoring.color(for: PrayerScoring.score(start: start, end: end, markedAt: marked))
    }

    var body: some View {
        let r = size * Self.radius / Self.size, d = r * 2
        ZStack {
            track.frame(width: d, height: d)
            ForEach(Array(zones.enumerated()), id: \.offset) { _, z in
                let color = PrayerScoring.color(for: z.score)
                let a0 = z.from + Self.gap / 2, a1 = z.to - Self.gap / 2, lit = min(a1, isQaza ? 360 : angle)
                arc(a0, a1).stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: theme.arc.width, lineCap: theme.arc.cap))
                    .frame(width: d, height: d)
                if lit > a0 + 0.5 {
                    arc(a0, lit).stroke(color, style: StrokeStyle(lineWidth: theme.arc.width, lineCap: theme.arc.cap))
                        .frame(width: d, height: d)
                        .shadow(color: color.opacity(theme.arc.glow), radius: 6)
                }
            }
            Circle()
                .fill(Color(.systemGroupedBackground))
                .overlay(Circle().strokeBorder(dotColor, lineWidth: 2.8))
                .frame(width: 15, height: 15)
                .scaleEffect(dragging ? 1.35 : 1)
                .offset(x: r * sin(angle * .pi / 180), y: -r * cos(angle * .pi / 180))
                .animation(.snappy(duration: 0.12), value: angle)
                .animation(.snappy(duration: 0.2), value: dragging)
        }
        .frame(width: size, height: size)
        // Only the band takes the finger (the wheel inside sits above it and takes its own): a touch that starts near the ring
        // drags the dot; anywhere else it does nothing.
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let c = CGPoint(x: size / 2, y: size / 2)
                    let start = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y)
                    guard abs(start - r) < 34 else { return }
                    if !dragging { dragging = true; triggerSomeVibration(type: .light) }
                    var a = atan2(v.location.x - c.x, -(v.location.y - c.y)) * 180 / .pi
                    if a < 0 { a += 360 }
                    // Near the top, the side the dot is on wins: no jump from the end back to the start.
                    if angle > 300 && a < 60 { a = 360 } else if angle < 60 && a > 300 { a = 0 }
                    onPick(a / 360)
                }
                .onEnded { _ in
                    if dragging { onRelease() }
                    dragging = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The prayer's window")
        .accessibilityValue(shortTimePM(marked))
    }

    /// The Salah page's track in the theme: the soft raised band, or the plain grey one.
    @ViewBuilder private var track: some View {
        if theme.track.lifted {
            Circle()
                .stroke(lineWidth: theme.track.width)
                .foregroundStyle(theme.surface)
                .shadow(color: theme.shade, radius: 4, x: 2, y: 2)
                .shadow(color: theme.light, radius: 6, x: -2, y: -2)
        } else {
            Circle().stroke(theme.track.fill, lineWidth: theme.track.width)
        }
    }

    private func arc(_ from: Double, _ to: Double) -> some Shape {
        Circle().trim(from: from / 360, to: to / 360).rotation(.degrees(-90))
    }
}

/// Cancel / Save as capsules: Save gray until there's something to save, then a green edge and
/// green text (owner — the solid green fill shouted).
struct SaveCancelButtons: View {
    let canSave: Bool
    var saveTitle = "Save"
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onCancel) {
                Text("Cancel")
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.primary)
                    .background(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                    .contentShape(Capsule())
            }
            Button(action: onSave) {
                Text(saveTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(canSave ? Color.green : Color.secondary)
                    .background(Capsule().strokeBorder(canSave ? Color.green : Color(.separator),
                                                       lineWidth: canSave ? 1.5 : 1))
                    .contentShape(Capsule())
            }
            .disabled(!canSave)
            .animation(.easeInOut(duration: 0.2), value: canSave)
        }
        .buttonStyle(.plain)
    }
}

/// The prayer's window as a bar: Perfect (first 30 min) green, Middle yellow, Closing red, with a
/// marker where the picked time falls. A time after the window (Qaza) parks the marker at the
/// end, gray, with "qaza" under it — the bar itself only shows the window.
struct PrayerWindowBar: View {
    let start: Date
    let end: Date
    /// Moves the shown start / end (the tour's practice clock).
    var labelShift: TimeInterval = 0
    let marked: Date
    let color: Color
    /// Tap or drag on the bar: the fraction of the window under the finger, 0…1.
    var onPick: (Double) -> Void = { _ in }

    var body: some View {
        let total = max(end.timeIntervalSince(start), 1)
        let early = min(PrayerScoring.earlyWindow / total, 1)
        let mid = early + (1 - early) / 2
        let position = min(max(marked.timeIntervalSince(start) / total, 0), 1)
        let isQaza = marked > end
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        Capsule().fill(Color.green.opacity(0.35)).frame(width: max(w * early - 2, 0))
                        if early < 1 {
                            Capsule().fill(Color.yellow.opacity(0.35)).frame(width: max(w * (mid - early) - 2, 0))
                            Capsule().fill(Color.red.opacity(0.35))
                        }
                    }
                    .frame(height: 6)
                    Circle()
                        .fill(Color(.systemBackground))
                        .overlay(Circle().stroke(color, lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .shadow(color: color.opacity(0.4), radius: 4)
                        .offset(x: w * position - 8)
                        .animation(.snappy(duration: 0.12), value: position)
                }
                .frame(height: 16)
                // A taller touch target than the 6 pt bar; tap to jump, drag to scrub.
                .contentShape(Rectangle().inset(by: -14))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in onPick(min(max(value.location.x / max(w, 1), 0), 1)) }
                )
            }
            .frame(height: 16)
            HStack {
                Text(shortTimePM(start.addingTimeInterval(labelShift)))
                Spacer()
                Text(isQaza ? "qaza" : shortTimePM(end.addingTimeInterval(labelShift)))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: isQaza)
            }
            .font(.caption2)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Time wheel

/// A continuous hour / minute / AM-PM wheel, like the system time wheel: hours loop and AM/PM
/// follows as you scroll past 12, so 11 PM → 12 AM → 1 AM is one scroll. Times outside `range`
/// (before the prayer, after now or the rollover) are grayed but never corrected — the sheet
/// disables Save instead (owner: auto-snapping "doesn't change the wheel" felt wrong; a
/// one-day system wheel snapped Isha's 12 AM back to the start). A picked time lands on the
/// prayer's day or the next, whichever is in range; if neither, `time` is the prayer's-day
/// version and is out of range.
struct PrayerTimeWheel: UIViewRepresentable {
    @Binding var time: Date
    /// Any instant on the prayer's calendar day.
    let day: Date
    let range: ClosedRange<Date>
    /// Inside the editor's ring (owner, 2026-10-19, direction A: "smaller wheel"): 22 pt rows, the picked row 19 pt and its
    /// neighbours 15, the columns close together.
    var compact = false
    /// The AM / PM column (only when the editable range crosses noon or midnight); hours still loop through all 24.
    var meridiem = true

    private static let loops = 200   // rows = 24 × loops (hours), 60 × loops (minutes)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        context.coordinator.show(time, in: picker)
        return picker
    }

    /// Exactly the size it's given: left to itself the picker keeps its own 216 pt height, which reached past the editor's
    /// ring band and took drags meant for the dot.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: proposal.height ?? 216)
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if time != context.coordinator.shown { context.coordinator.show(time, in: picker) }
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: PrayerTimeWheel
        var shown: Date?
        private var hour24 = 0, minute = 0
        private let cal = Calendar.current

        init(_ parent: PrayerTimeWheel) { self.parent = parent }

        /// The instant for this clock time on the prayer's day or the next, if either is in range.
        private func validDate(_ h: Int, _ m: Int) -> Date? {
            let base = cal.startOfDay(for: parent.day)
            for offset in 0...1 {
                guard let d = cal.date(byAdding: .day, value: offset, to: base),
                      let t = cal.date(bySettingHour: h, minute: m, second: 0, of: d) else { continue }
                if parent.range.contains(t) { return t }
            }
            return nil
        }
        private func dayDate(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: cal.startOfDay(for: parent.day)) ?? parent.day
        }
        /// Cached per hour (the range doesn't change while the sheet is up): each hour row used to
        /// run 60 × 2 calendar lookups every time it was drawn.
        private var hourValidity: [Int: Bool] = [:]
        private func hourValid(_ h: Int) -> Bool {
            if let known = hourValidity[h] { return known }
            let v = (0..<60).contains { validDate(h, $0) != nil }
            hourValidity[h] = v
            return v
        }

        /// Put the wheel on `t` (middle of the loops). The first time reloads everything; after
        /// that (the bar scrubbing) it only selects rows, and refreshes the minutes' graying only
        /// when the hour changed — a full reload per minute hung the bar on device.
        private var loaded = false
        func show(_ t: Date, in picker: UIPickerView) {
            let c = cal.dateComponents([.hour, .minute], from: t)
            let hourChanged = (c.hour ?? 0) != hour24
            hour24 = c.hour ?? 0
            minute = c.minute ?? 0
            shown = t
            if !loaded {
                picker.reloadAllComponents()
                loaded = true
            } else if hourChanged {
                picker.reloadComponent(1)
            }
            picker.selectRow(24 * (PrayerTimeWheel.loops / 2) + hour24, inComponent: 0, animated: false)
            picker.selectRow(60 * (PrayerTimeWheel.loops / 2) + minute, inComponent: 1, animated: false)
            if parent.meridiem { picker.selectRow(hour24 >= 12 ? 1 : 0, inComponent: 2, animated: false) }
            if parent.compact {   // the picked rows' size (five rows each, cheap)
                picker.reloadComponent(1)
                if hourChanged { picker.reloadComponent(0) }
            }
        }

        private func publish(_ picker: UIPickerView) {
            let t = validDate(hour24, minute) ?? dayDate(hour24, minute)
            shown = t
            parent.time = t
            picker.reloadComponent(0)
            picker.reloadComponent(1)
        }

        // MARK: data source / delegate
        func numberOfComponents(in pickerView: UIPickerView) -> Int { parent.meridiem ? 3 : 2 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            [24 * PrayerTimeWheel.loops, 60 * PrayerTimeWheel.loops, 2][component]
        }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { parent.compact ? 40 : 64 }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { parent.compact ? 22 : 36 }

        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            let text: String, valid: Bool
            switch component {
            case 0:
                let h = row % 24
                text = "\(h % 12 == 0 ? 12 : h % 12)"
                valid = hourValid(h)
            case 1:
                let m = row % 60
                text = String(format: "%02d", m)
                valid = validDate(hour24, m) != nil
            default:
                text = row == 0 ? "AM" : "PM"
                valid = true
            }
            label.text = text
            label.textAlignment = .center
            let size: CGFloat = parent.compact ? (row == pickerView.selectedRow(inComponent: component) ? 19 : 15) : 23
            let base = UIFont.systemFont(ofSize: size, weight: parent.compact ? .light : .regular)
            label.font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size)
            label.textColor = valid ? .label : .tertiaryLabel
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            switch component {
            case 0:
                hour24 = row % 24
                // AM/PM follows the hour, like the system wheel.
                if parent.meridiem { pickerView.selectRow(hour24 >= 12 ? 1 : 0, inComponent: 2, animated: true) }
            case 1:
                minute = row % 60
            default:
                if parent.compact { pickerView.reloadComponent(2) }
                // Tapping AM/PM moves the hour 12 either way, to the nearer row.
                let wantPM = row == 1
                if (hour24 >= 12) != wantPM {
                    let current = pickerView.selectedRow(inComponent: 0)
                    let target = wantPM ? current + 12 : current - 12
                    hour24 = (hour24 + 12) % 24
                    pickerView.selectRow(target, inComponent: 0, animated: true)
                }
            }
            publish(pickerView)
        }
    }
}


/// The editor's sheet in Liquid Glass: nothing painted on iOS 26 (the partial sheet is glass), a material before (as the
/// top-up sheet, AutoTopUp's TopUpSheetGlass).
private struct EditorSheetGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content } else { content.presentationBackground(.regularMaterial) }
    }
}
