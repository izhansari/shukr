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
    @Binding var time: Date
    /// The time being picked lives here until ✓ (owner saw the bar hang on device: every minute scrubbed wrote the parent's
    /// state and re-rendered the prayer row behind the sheet).
    @State private var draft: Date
    /// From the prayer's start (never earlier) to now or the next Fajr (the day's rollover), whichever is first. After the
    /// window it's Qaza, e.g. Isha at 12:30 AM.
    let range: ClosedRange<Date>
    var onCancel: () -> Void
    /// The time, and the new spot if the pin was moved (nil = where it was).
    var onSave: (Date, CLLocationCoordinate2D?) -> Void

    /// Where it was prayed: the Where row opens `PrayerLocationPicker`; the picked spot waits here and is saved with ✓, like
    /// the time. Off when the sheet is opened from the prayer map, which moves pins on the map itself.
    var showsLocation = true
    @State private var draftSpot: CLLocationCoordinate2D?
    @State private var pickingSpot = false
    @State private var spotName: String?
    private var savedSpot: CLLocationCoordinate2D? {
        guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var shownSpot: CLLocationCoordinate2D? { draftSpot ?? savedSpot }

    /// The prayer's photo (PrayerPhotos.swift): added or retaken while the prayer's window is on and it's marked (owner: "they
    /// can add photos any time in that window so long as its marked"), seen any time after. Saved at once, never by ✓.
    @State private var photoTarget: PrayerPhotoTarget?
    @State private var askPhoto = false
    @State private var photoSaved = false
    private var photoKey: String { PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name) }
    private var photoInWindow: Bool { prayer.isCompleted && Date() < prayer.endTime }

    /// The note (the photos' note file, PrayerPhotos.note — the day page and Journey read it): edited in its row, saved by ✓
    /// or the keyboard's Done.
    @State private var draftNote = ""
    @State private var savedNote = ""
    @FocusState private var noteFocused: Bool

    @State private var askDiscard = false
    @State private var contentHeight: CGFloat = 0
    @State private var detent: PresentationDetent = .large

    init(prayer: PrayerModel, time: Binding<Date>, range: ClosedRange<Date>, showsLocation: Bool = true,
         onCancel: @escaping () -> Void, onSave: @escaping (Date, CLLocationCoordinate2D?) -> Void) {
        self.prayer = prayer
        self.showsLocation = showsLocation
        self._time = time
        // Open on the time saved for this prayer (owner, 2026-09-26). The parent's binding isn't enough: it's written in the
        // same long-press that presents the sheet, and the sheet came up with the value from before — the device's time.
        // Kept within what can be saved.
        let saved = prayer.timeAtComplete ?? time.wrappedValue
        self._draft = State(initialValue: min(max(saved, range.lowerBound), range.upperBound))
        self.range = range
        self.onCancel = onCancel
        self.onSave = onSave
        let note = PrayerPhotos.note(PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name)) ?? ""
        self._draftNote = State(initialValue: note)
        self._savedNote = State(initialValue: note)
    }

    private var isValid: Bool { range.contains(draft) }
    /// The time the sheet opened with; ✓ stays away until a different (valid) one is picked.
    @State private var openedWith: Date?
    private var timeChanged: Bool {
        guard let openedWith else { return false }
        return abs(draft.timeIntervalSince(openedWith)) >= 30
    }
    private var noteChanged: Bool { draftNote.trimmingCharacters(in: .whitespacesAndNewlines) != savedNote }
    private var hasEdits: Bool { timeChanged || draftSpot != nil || noteChanged }
    /// The tour's fix step saves any changed time (tour v2, owner: "change its time, and save"). The tour's Fajr fix saves
    /// only a time in the yellow (owner, 2026-10-06), until it's done.
    private var canSave: Bool {
        isValid && hasEdits && (!TourRuntime.shared.needsYellow(prayer) || draftInYellow)
    }
    private var draftInYellow: Bool {
        PrayerScoring.grade(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)) == .onTime
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The tour's fix step is in this sheet: its tip continues here (audit J: "nothing goes silent"). The step is the time
    /// alone (owner: only the intended thing): no card.
    private var tourTip: Bool { TourRuntime.shared.step == .list && TourRuntime.isPracticeAnywhere(prayer) }
    private var shift: TimeInterval { PracticeClock.shift(for: prayer) }

    private var subtitle: String {
        "\(shortTimePM(prayer.startTime.addingTimeInterval(shift))) – \(shortTimePM(prayer.endTime.addingTimeInterval(shift))) · when did you pray?"
    }

    var body: some View {
        VStack(spacing: 16) {
            // The tour's words for this step are in its panel, over the sheet (TourEditorPanelWindow).
            MapSheetHeader(title: prayer.displayName, subtitle: subtitle) {
                HStack(spacing: 10) {
                    MapSheetCircleButton(symbol: "xmark", label: "Close") { close() }
                    if canSave {
                        MapSheetCircleButton(symbol: "checkmark", label: "Save", tint: .sage, fill: Color.sage.opacity(0.16)) { save() }
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.22), value: canSave)
            }
            .padding(.top, 22)

            PrayerTimeEditor(prayer: prayer, draft: $draft, range: range)

            if !tourTip { card }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .fontDesign(.rounded)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            if openedWith == nil { openedWith = draft }
            if tourTip { TourEditorPanelWindow.show() }
        }
        .onDisappear { TourEditorPanelWindow.hide() }
        .onChange(of: draftInYellow, initial: true) { _, now in if tourTip { TourRuntime.shared.editorInYellow = now } }
        .onChange(of: draft, initial: true) { _, now in
            guard tourTip else { return }
            TourRuntime.shared.editorScore = PrayerScoring.points(for: PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: now))
        }
        // Writing a note needs the keyboard's room: the sheet goes full height while the field is up.
        .onChange(of: noteFocused) { _, on in withAnimation(.smooth(duration: 0.3)) { detent = on ? .large : fitted } }
        .onChange(of: contentHeight) { _, _ in if !noteFocused { detent = fitted } }
        .sheet(isPresented: $pickingSpot) {
            PrayerLocationPicker(prayerName: prayer.displayName, original: shownSpot,
                                 recorded: prayer.recordedSpot ?? savedSpot,
                                 onCancel: { pickingSpot = false },
                                 onPick: { spot in draftSpot = spot; pickingSpot = false })
                .presentationDetents([.large])
                .interactiveDismissDisabled()
        }
        .task(id: shownSpot.map { "\($0.latitude),\($0.longitude)" }) {
            spotName = nil
            if let spot = shownSpot { spotName = await PrayerPlaceNames.named(spot) }
        }
        .fullScreenCover(item: $photoTarget, onDismiss: flashPhotoSaved) { target in
            PrayerPhotoCapture(target: target) { photoTarget = nil }
        }
        .confirmationDialog("Your photo", isPresented: $askPhoto, titleVisibility: .hidden) {
            Button("Retake") { photoTarget = PrayerPhotoTarget.forMarked(prayer) }
            Button("Remove", role: .destructive) {
                PrayerPhotos.delete(photoKey)
                flashPhotoSaved()
            }
        }
        // ✕ with an unsaved edit (owner, 2026-10-19: "A").
        .alert("Discard your changes?", isPresented: $askDiscard) {
            Button("Discard", role: .destructive) { onCancel() }
            Button("Keep editing", role: .cancel) {}
        }
        // The tour's tip at the largest text: the full height, else ✓ fell off the sheet (Sami, AX XXXL).
        .presentationDetents(tourTip && typeSize.isAccessibilitySize ? [.large] : [fitted, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .presentationCornerRadius(28)
    }

    /// The sheet fitted to what it holds.
    private var fitted: PresentationDetent { contentHeight > 0 ? .height(min(contentHeight + 8, 760)) : .large }

    private func close() {
        if hasEdits { askDiscard = true } else { onCancel() }
    }

    private func save() {
        guard canSave else { return }
        if noteChanged { commitNote() }
        onSave(draft, draftSpot)
    }

    private func commitNote() {
        PrayerPhotos.setNote(photoKey, draftNote)
        savedNote = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        draftNote = savedNote
    }

    private func flashPhotoSaved() {
        withAnimation(.easeOut(duration: 0.2)) { photoSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { photoSaved = false }
        }
    }

    // MARK: The card

    /// One flat card under the ring: Where · Photo · Note.
    private var card: some View {
        VStack(spacing: 0) {
            if showsLocation {
                whereRow
                Divider().padding(.leading, 52)
            }
            photoRow
            Divider().padding(.leading, 52)
            noteRow
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func cardRow<Lead: View, Trail: View>(@ViewBuilder lead: () -> Lead, title: String, detail: String?,
                                                  titleTint: Color = .primary,
                                                  @ViewBuilder trailing: () -> Trail) -> some View {
        HStack(spacing: 12) {
            lead().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(titleTint).lineLimit(1)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// Where: the masjid, else the place's name (PrayerPlaceNames — the name every "where" reads); Move opens the picker.
    private var whereRow: some View {
        // Before a move the stored masjid is right; after one, only your own masajid are known yet.
        let masjid = draftSpot == nil ? (prayer.atMasjid ? prayer.mosqueName : nil)
                                      : draftSpot.flatMap { MasjidDetector.favoriteMasjid(near: $0) }
        let title = shownSpot == nil ? "Add where you prayed" : (masjid ?? spotName ?? "Pinned on the map")
        let detail: String? = draftSpot != nil ? "Moved · saves with ✓" : (prayer.spotEdited ? "Edited" : nil)
        return Button { pickingSpot = true } label: {
            cardRow(lead: {
                Image(systemName: masjid != nil ? "building.columns.fill" : "mappin.and.ellipse")
                    .font(.system(size: 17)).foregroundStyle(masjid != nil ? Color.sage : .secondary)
            }, title: title, detail: detail) {
                HStack(spacing: 4) {
                    Text(shownSpot == nil ? "Add" : "Move")
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Photo: added, retaken or removed while the prayer is on; each saves at once (a quiet "Saved"), never through ✓.
    private var photoRow: some View {
        let _ = PrayerPhotoRevision.shared.value
        let has = PrayerPhotos.has(photoKey)
        let detail: String = photoSaved ? "Saved"
            : has ? (photoInWindow ? "Retake or remove while \(prayer.displayName) is on" : takenLine)
                  : (photoInWindow ? "While \(prayer.displayName) is on" : "Only while \(prayer.displayName) is on")
        return Button {
            guard photoInWindow else { return }
            triggerSomeVibration(type: .light)
            if has { askPhoto = true } else { photoTarget = PrayerPhotoTarget.forMarked(prayer) }
        } label: {
            cardRow(lead: {
                if has {
                    PrayerPhotoCard(key: photoKey, width: 28)
                } else {
                    Image(systemName: "camera").font(.system(size: 16)).foregroundStyle(.secondary)
                }
            }, title: has ? "Your photo" : "Add a photo", detail: detail,
               titleTint: has || photoInWindow ? .primary : .secondary) {
                if photoInWindow {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .animation(.easeOut(duration: 0.2), value: photoSaved)
        }
        .buttonStyle(.plain)
        .disabled(!photoInWindow)
    }

    /// "Taken at 6:58 PM": the photo file's own time.
    private var takenLine: String {
        let url = PrayerPhotos.url(photoKey, front: false)
        let at = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date
        return at.map { "Taken at \(shortTimePM($0))" } ?? "Seen any time"
    }

    /// Note: one line; a tap makes it the text field (the keyboard's Done saves it, as ✓ does).
    private var noteRow: some View {
        cardRow(lead: {
            Image(systemName: "text.quote").font(.system(size: 16)).foregroundStyle(.secondary)
        }, title: "", detail: nil) { EmptyView() }
        .overlay(alignment: .leading) {
            TextField("Add a note", text: $draftNote)
                .font(.body)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { if noteChanged { commitNote() } }
                .padding(.leading, 52)
                .padding(.trailing, 12)
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

    /// Why an out-of-range time can't be saved: nearer (on the clock) to the start → it's before the prayer; nearer the other
    /// end → it hasn't happened yet, or it's past the day's rollover.
    private var invalidReason: String {
        let cal = Calendar.current
        func clock(_ d: Date) -> Double {
            let c = cal.dateComponents([.hour, .minute], from: d)
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        func dist(_ a: Date, _ b: Date) -> Double { let x = abs(clock(a) - clock(b)); return min(x, 1440 - x) }
        if dist(draft, range.lowerBound) <= dist(draft, range.upperBound) {
            return "That's before \(prayer.name) started at \(shortTimePM(range.lowerBound.addingTimeInterval(shift)))."
        }
        // The upper bound is now unless the day already rolled over before now.
        if range.upperBound < Date().addingTimeInterval(-60) {
            return "That's after Fajr at \(shortTimePM(range.upperBound.addingTimeInterval(shift))) — the next day had started."
        }
        return "That hasn't happened yet — it's \(shortTimePM(range.upperBound.addingTimeInterval(shift))) now."
    }

    var body: some View {
        let grade = PrayerScoring.grade(for: score)
        VStack(spacing: 12) {
            ZStack {
                PrayerWindowRing(start: prayer.startTime, end: prayer.endTime, marked: draft, valid: isValid,
                                 onPick: pickFromRing)
                VStack(spacing: 6) {
                    // The tour's practice prayer reads on its plain clock (PracticeClock): the wheel shows, and picks,
                    // shifted times.
                    PrayerTimeWheel(time: Binding(get: { draft.addingTimeInterval(shift) }, set: { draft = $0.addingTimeInterval(-shift) }),
                                    day: prayer.startTime.addingTimeInterval(shift),
                                    range: range.lowerBound.addingTimeInterval(shift)...range.upperBound.addingTimeInterval(shift),
                                    compact: true, meridiem: showsMeridiem)
                        .frame(width: showsMeridiem ? 132 : 92, height: 110)
                        // The wheel keeps to its box (UIPickerView draws past it), its rows fading out top and bottom.
                        .clipped()
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28),
                                                     .init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                    if showsScore {
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
                .offset(y: showsScore ? 8 : 0)
            }
            .frame(width: PrayerWindowRing.size, height: PrayerWindowRing.size)
            .frame(maxWidth: .infinity)

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

            if !isValid {
                // Out of range: say what is allowed (✓ stays away until then).
                Text(invalidReason)
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            } else if !Calendar.current.isDate(draft, inSameDayAs: prayer.startTime) {
                // After midnight, say which day and time this actually is.
                Text(draft.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.footnote)
                    .fontWeight(.light)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: grade)
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
    /// The finger on the ring: the fraction of the window under it, 0…1 (never past the end).
    var onPick: (Double) -> Void = { _ in }
    @Environment(\.circleTheme) private var theme
    @State private var dragging = false

    static let size: CGFloat = 260
    static let radius: CGFloat = 106
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
        let r = Self.radius, d = r * 2
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
        .frame(width: Self.size, height: Self.size)
        // Only the band takes the finger (the wheel inside sits above it and takes its own): a touch that starts near the ring
        // drags the dot; anywhere else it does nothing.
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    let c = CGPoint(x: Self.size / 2, y: Self.size / 2)
                    let start = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y)
                    guard abs(start - r) < 34 else { return }
                    if !dragging { dragging = true; triggerSomeVibration(type: .light) }
                    var a = atan2(v.location.x - c.x, -(v.location.y - c.y)) * 180 / .pi
                    if a < 0 { a += 360 }
                    // Near the top, the side the dot is on wins: no jump from the end back to the start.
                    if angle > 300 && a < 60 { a = 360 } else if angle < 60 && a > 300 { a = 0 }
                    onPick(a / 360)
                }
                .onEnded { _ in dragging = false }
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
