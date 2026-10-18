import SwiftUI
import MapKit

// Journey's prayer sheet (phase 2; spec screen 3, mock-ups Sheet5 / Sheet5Mark): one half sheet for a marked prayer and an
// unmarked one, on any day. Top right only the trash (unmark — it removes the prayer's data); once something is edited,
// Cancel · Save come in at the bottom, the Salah page editor's own buttons (owner, round 3). Nothing is saved until Save:
// the time (the window bar or the wheel), the place and the note are drafts; a swipe down closes it only while nothing is
// edited, so leaving edits is always the user's own Cancel. No sage on the sheet (owner). The score ring and the window
// bar (no sentence — owner: it got old); "Prayed at <time> ⌄" opens the wheel (the sheet grows to full height, only the
// time shows); the place as a map card that grows in place (movable, the pin kept), the photo as itself (it opens in
// place) — two different things, drawn differently (owner). An unmarked past prayer defaults to made up today = Qaza
// (owner), marked with its pill.

extension Notification.Name {
    /// A prayer was marked, unmarked or edited (anywhere: the Salah page, Journey, a widget / watch mark reconciled): its
    /// pages read their rows again. Post it through `JourneyChange.post()`.
    static let journeyChanged = Notification.Name("journeyChanged")
}

/// One `.journeyChanged` per change: every mark, unmark and time edit posts here, and the posts of one turn of the main
/// thread go out as one (a mark from Journey's sheet runs the view model's path, which posts, and then the sheet's own).
/// A mark on the Salah page posted nothing, and Journey in the pager kept its old numbers until a relaunch (sim,
/// 2026-10-18). Journey reads it only while it's on screen; under another page it marks itself dirty for the way back.
enum JourneyChange {
    /// Main thread only (every mark path runs there).
    nonisolated(unsafe) private static var pending = false
    static func post() {
        assert(Thread.isMainThread)
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async {
            pending = false
            NotificationCenter.default.post(name: .journeyChanged, object: nil)
        }
    }
}

struct JourneyPrayerSheet: View {
    let prayer: PrayerModel
    @EnvironmentObject private var viewModel: PrayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.circleTheme) private var theme
    @Namespace private var mapSpace

    /// The time being picked (saved with Save / Mark).
    @State private var draft: Date
    @State private var wheelOpen = false
    @State private var mapOpen = false
    @State private var detent: PresentationDetent
    /// Half height; a little taller once Cancel · Save (or the Mark pill) sit at the bottom, so they never cover the note.
    private static let resting = PresentationDetent.height(480)
    private static let withButtons = PresentationDetent.height(548)
    @State private var pickingSpot = false
    /// A spot picked here, saved with Save / Mark.
    @State private var draftSpot: CLLocationCoordinate2D?
    @State private var editingNote = false
    @State private var noteText = ""
    /// The note as it will be saved (nil = none).
    @State private var note: String?
    @State private var confirmUnmark = false
    @State private var photoTarget: PrayerPhotoTarget?
    @State private var places = 0   // bumps as a place name arrives
    /// What it opened with (Save lights up on a difference).
    private let openedWith: Date
    private let savedNote: String?

    init(prayer: PrayerModel) {
        self.prayer = prayer
        // Marked: its time. Unmarked: now — after the window that's made up today, Qaza (owner: the default; another day
        // and time stay behind "Prayed at", never the main choice).
        let start = prayer.timeAtComplete ?? Date()
        _draft = State(initialValue: start)
        openedWith = start
        _detent = State(initialValue: prayer.isCompleted ? Self.resting : Self.withButtons)
        let stored = PrayerPhotos.note(PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name))
        savedNote = stored
        _note = State(initialValue: stored)
    }

    private var marked: Bool { prayer.isCompleted }
    private var restingDetent: PresentationDetent { !marked || edited ? Self.withButtons : Self.resting }
    private var excused: Bool { !marked && Excused.covers(start: prayer.startTime, end: prayer.endTime) }
    private var range: ClosedRange<Date> { prayer.startTime...max(prayer.startTime, Date()) }
    private var jumuah: Bool { marked && prayer.isJumuah && draftSpot == nil }
    private var score: Double {
        jumuah ? 1 : PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)
    }
    private var photoKey: String { PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name) }
    private var savedSpot: CLLocationCoordinate2D? {
        guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var shownSpot: CLLocationCoordinate2D? { draftSpot ?? savedSpot }
    private var timeChanged: Bool { abs(draft.timeIntervalSince(openedWith)) >= 30 }
    /// Anything that differs from what's stored (a marked prayer's Save).
    private var edited: Bool { timeChanged || draftSpot != nil || note != savedNote }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 20)
            ZStack(alignment: .top) {
                if mapOpen, let spot = shownSpot {
                    bigMap(spot)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            scoreRow.padding(.top, 16)
                            timeRow.padding(.top, 14)
                            if wheelOpen { wheel }
                            if !wheelOpen && !excused { extras }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            if !mapOpen {
                if !marked {
                    markPill.padding(.horizontal, 22).padding(.bottom, 10)
                } else if edited {
                    SaveCancelButtons(canSave: edited, onCancel: { dismiss() }, onSave: save)
                        .padding(.horizontal, 22).padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .presentationDetents([Self.resting, Self.withButtons, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        // Edits are left only by the user's own ✕ (owner: "so long as I press cancel myself").
        .interactiveDismissDisabled(marked && edited)
        .animation(.easeInOut(duration: 0.25), value: edited)
        .onChange(of: wheelOpen || mapOpen) { _, big in
            withAnimation(.easeInOut(duration: 0.3)) { detent = big ? .large : restingDetent }
        }
        .onChange(of: edited) {
            guard detent != .large else { return }
            withAnimation(.easeInOut(duration: 0.25)) { detent = restingDetent }
        }
        .sheet(isPresented: $pickingSpot) {
            PrayerLocationPicker(prayerName: prayer.displayName, original: shownSpot, recorded: prayer.recordedSpot ?? savedSpot,
                                 onCancel: { pickingSpot = false },
                                 onPick: { spot in
                                     draftSpot = spot
                                     PrayerPlaceNames.fill([spot]) { places += 1 }
                                     pickingSpot = false
                                 })
        }
        .fullScreenCover(item: $photoTarget) { target in
            PrayerPhotoCapture(target: target) { photoTarget = nil }
        }
        .alert("Note", isPresented: $editingNote) {
            TextField("A few words about this prayer", text: $noteText, axis: .vertical)
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                note = trimmed.isEmpty ? nil : trimmed
            }
        }
        .alert("Unmark \(prayer.displayName)?", isPresented: $confirmUnmark) {
            Button("Cancel", role: .cancel) {}
            Button("Unmark", role: .destructive, action: unmark)
        } message: {
            Text(PrayerPhotos.has(photoKey) ? "Its photo will be deleted too." : "It will count as not prayed.")
        }
        .task { if let spot = savedSpot { PrayerPlaceNames.fill([spot]) { places += 1 } } }
        .sensoryFeedback(.selection, trigger: PrayerScoring.grade(for: score))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(jumuah ? "Jumu'ah" : prayer.name)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if mapOpen {
                circleButton("chevron.down", label: "Close the map") {
                    withAnimation(.easeInOut(duration: 0.35)) { mapOpen = false }
                }
            } else {
                if marked {
                    circleButton("trash", tint: .red, label: "Unmark and delete") {
                        // The list's own card (Sami's UnmarkPrompt, with the photo when there is one); another overlay
                        // up: the system alert.
                        if !UnmarkPrompt.ask(for: prayer, onUnmark: unmark) { confirmUnmark = true }
                    }
                }
            }
        }
    }

    private func circleButton(_ symbol: String, tint: Color? = nil, filled: Bool = false, label: String,
                              action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(filled ? (tint ?? .primary).opacity(0.16) : Color.primary.opacity(0.07)))
                .overlay { if filled { Circle().strokeBorder((tint ?? .primary).opacity(0.6), lineWidth: 1.2) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var subtitle: String {
        let day = prayer.dayStart.addingTimeInterval(12 * 3600).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if excused { return "\(day) · excused" }
        if marked && edited { return "\(day) · not saved" }
        return marked ? day : "\(day) · not marked"
    }

    // MARK: Score

    private var scoreRow: some View {
        let color = PrayerScoring.color(for: score)
        return HStack(spacing: 16) {
            ZStack {
                NeuPressed(shape: Circle(), radius: 4, offset: 3)
                Circle().trim(from: 0, to: excused ? 0 : score)
                    .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(7)
                VStack(spacing: 0) {
                    Text(excused ? "–" : "\(PrayerScoring.points(for: score))")
                        .font(.system(size: 22, weight: .thin, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: score))
                    Text(excused ? "excused" : jumuah ? "Jumu'ah" : PrayerScoring.grade(for: score).rawValue)
                        .font(.system(size: 10, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)
            .animation(.snappy, value: score)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(excused ? "Excused" : PrayerScoring.summary(for: score))
            PrayerWindowBar(start: prayer.startTime, end: prayer.endTime, marked: draft,
                            color: excused ? Color(.tertiaryLabel) : color) { fraction in
                guard !excused, !jumuah else { return }
                let raw = prayer.startTime.addingTimeInterval(prayer.endTime.timeIntervalSince(prayer.startTime) * fraction)
                let minute = Date(timeIntervalSinceReferenceDate: (raw.timeIntervalSinceReferenceDate / 60).rounded() * 60)
                let picked = min(max(minute, range.lowerBound), range.upperBound)
                if picked != draft { draft = picked }
            }
        }
    }

    // MARK: Time

    private var timeRow: some View {
        Button {
            guard !excused, !jumuah else { return }
            triggerSomeVibration(type: .light)
            withAnimation(.easeInOut(duration: 0.3)) { wheelOpen.toggle() }
        } label: {
            HStack {
                Text("Prayed at")
                    .font(.system(size: 16, weight: .light, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    Text(timeText)
                        .font(.system(size: 16, weight: .light, design: .rounded))
                        .monospacedDigit()
                    if !excused && !jumuah {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(wheelOpen ? 180 : 0))
                    }
                }
                // Made up today (the default) reads quietly: picking another day and time is there, not the main choice.
                .foregroundStyle(excused || jumuah || madeUpToday ? Color.secondary : Color.primary)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(excused)
    }

    /// An unmarked prayer left on its default: made up now, after its window.
    private var madeUpToday: Bool { !marked && !wheelOpen && draft > prayer.endTime && Calendar.current.isDateInToday(draft) }

    /// "6:15 AM" on its own day; "Today, 3:12 PM" / "Sat 6:15 AM" on another.
    private var timeText: String {
        if excused { return "–" }
        if Calendar.current.isDate(draft, inSameDayAs: prayer.startTime) { return shortTimePM(draft) }
        if Calendar.current.isDateInToday(draft) { return "Today, \(shortTimePM(draft))" }
        return "\(draft.formatted(.dateTime.weekday(.abbreviated))) \(shortTimePM(draft))"
    }

    @ViewBuilder private var wheel: some View {
        VStack(spacing: 8) {
            DatePicker("Prayed at", selection: $draft, in: range, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.035)))
            // The day's column runs to today: one tap to the prayer's own day (its start) and back to now.
            if !Calendar.current.isDate(draft, inSameDayAs: prayer.startTime) {
                quietLink("Prayed it on \(prayer.dayStart.addingTimeInterval(12 * 3600).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))? ›") {
                    draft = prayer.startTime
                }
            } else if !marked, prayer.endTime < Date(), !Calendar.current.isDateInToday(prayer.startTime) {
                quietLink("Made up today instead ›") { draft = Date() }
            }
            // Edited before: what the app recorded, one tap back to it.
            if marked, let recorded = prayer.recordedTimeAtComplete, abs(draft.timeIntervalSince(recorded)) >= 30 {
                Button {
                    draft = min(max(recorded, range.lowerBound), range.upperBound)
                } label: {
                    Label("You marked it at \(shortTimePM(recorded)) · use that", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    private func quietLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Place, photo, note

    private var extras: some View {
        VStack(spacing: 0) {
            placeAndPhoto
                .padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            noteRow.padding(.top, 14)
        }
        .transition(.opacity)
    }

    private var placeTitle: String {
        let _ = places
        guard let spot = shownSpot else { return "No place" }
        if draftSpot == nil, let m = prayer.mosqueName, !m.isEmpty { return m }
        if let masjid = draftSpot.flatMap({ MasjidDetector.favoriteMasjid(near: $0) }) { return masjid }
        return PrayerPlaceNames.name(spot) ?? "Pinned on the map"
    }

    /// The map as a card of its own (the place's name on it) and the photo as itself — two kinds of thing, never the same
    /// box (owner). No photo and none to take: the map has the row.
    @ViewBuilder private var placeAndPhoto: some View {
        let _ = PrayerPhotoRevision.shared.value
        let has = PrayerPhotos.has(photoKey)
        // A photo can be taken only while the prayer is on and marked (the camera's rule).
        let canTake = marked && Date() < prayer.endTime
        HStack(alignment: .center, spacing: 14) {
            if let spot = shownSpot {
                Button {
                    triggerSomeVibration(type: .light)
                    withAnimation(.easeInOut(duration: 0.4)) { mapOpen = true }
                } label: {
                    JourneyPlaceMap(spot: spot, title: placeTitle, score: excused ? nil : score,
                                    atMasjid: draftSpot == nil && prayer.atMasjid, interactive: false)
                        .matchedGeometryEffect(id: "map", in: mapSpace)
                        .frame(height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .allowsHitTesting(false)
                        .overlay(alignment: .bottomLeading) {
                            Text(placeTitle)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(.regularMaterial))
                                .padding(8)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(placeTitle), open the map")
            } else {
                Button {
                    triggerSomeVibration(type: .light)
                    pickingSpot = true
                } label: {
                    Label("Add where you prayed", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if has {
                // The photo itself; its own tap opens it in place (the viewer zooms out of it).
                PrayerPhotoCard(key: photoKey, width: 104)
            } else if canTake {
                Button {
                    triggerSomeVibration(type: .light)
                    photoTarget = PrayerPhotoTarget.forMarked(prayer)
                } label: {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 104, height: 104)
                        .overlay(Image(systemName: "camera").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take a photo")
            }
        }
    }

    private var noteRow: some View {
        Button {
            triggerSomeVibration(type: .light)
            noteText = note ?? ""
            editingNote = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Note").font(.system(size: 16, weight: .light, design: .rounded))
                Spacer(minLength: 0)
                Text(note ?? "Add a note")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(note == nil ? Color.secondary : Color.primary.opacity(0.75))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(3)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: The map, grown

    private func bigMap(_ spot: CLLocationCoordinate2D) -> some View {
        JourneyPlaceMap(spot: spot, title: placeTitle, score: score, atMasjid: draftSpot == nil && prayer.atMasjid, interactive: true)
            .matchedGeometryEffect(id: "map", in: mapSpace)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottom) {
                Button {
                    triggerSomeVibration(type: .light)
                    pickingSpot = true
                } label: {
                    Label("Move the pin", systemImage: "mappin.and.ellipse")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .mapGlass(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    // MARK: Saving

    /// An unmarked prayer's one action, in the Salah editor's Save look.
    private var markPill: some View {
        Button(action: mark) {
            Text(excused ? "Excused" : "Mark \(prayer.displayName)")
                .fontWeight(.semibold)
                .foregroundStyle(excused ? Color.secondary : Color.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().strokeBorder(excused ? Color(.separator) : Color.green, lineWidth: excused ? 1 : 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(excused)
    }

    private func save() {
        guard marked, edited else { return }
        if timeChanged, !jumuah { viewModel.editPrayerTime(prayer, to: draft) }
        if let draftSpot { viewModel.movePrayer(prayer, to: draftSpot) }
        if note != savedNote { PrayerPhotos.setNote(photoKey, note) }
        triggerSomeVibration(type: .success)
        JourneyChange.post()
        dismiss()
    }

    private func mark() {
        let when = min(max(draft, range.lowerBound), Date())
        guard viewModel.markFromJourney(prayer, at: when) else { return }
        if let draftSpot { viewModel.movePrayer(prayer, to: draftSpot) }
        if let note { PrayerPhotos.setNote(photoKey, note) }
        JourneyChange.post()
        dismiss()
    }

    private func unmark() {
        viewModel.unmarkFromJourney(prayer)
        JourneyChange.post()
        dismiss()
    }
}

/// The prayer's spot: small and still on the sheet's card, or grown and movable (the pin stays; the app map's capsule —
/// map style, then back to the pin). Markers as on PrayerPlaceMapSheet: the grade's color, masjid / hands.
struct JourneyPlaceMap: View {
    let spot: CLLocationCoordinate2D
    let title: String
    let score: Double?
    let atMasjid: Bool
    let interactive: Bool
    @AppStorage(MapModes.satelliteKey) private var satellite = false
    @State private var camera: MapCameraPosition
    @State private var awayFromPin = false

    init(spot: CLLocationCoordinate2D, title: String, score: Double?, atMasjid: Bool, interactive: Bool) {
        self.spot = spot
        self.title = title
        self.score = score
        self.atMasjid = atMasjid
        self.interactive = interactive
        _camera = State(initialValue: .region(Self.region(spot, interactive)))
    }

    private static func region(_ spot: CLLocationCoordinate2D, _ wide: Bool) -> MKCoordinateRegion {
        MKCoordinateRegion(center: spot, latitudinalMeters: wide ? 700 : 450, longitudinalMeters: wide ? 700 : 450)
    }

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? .all : []) {
            // Small, the name sits on the card itself (no label twice).
            Marker(interactive ? title : "", systemImage: atMasjid ? "building.columns.fill" : "hands.and.sparkles.fill", coordinate: spot)
                .tint(PrayerScoring.color(for: score))
        }
        .mapStyle(interactive && satellite ? .hybrid(elevation: .realistic) : .standard(pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .continuous) { context in
            guard interactive else { return }
            let centre = CLLocation(latitude: context.region.center.latitude, longitude: context.region.center.longitude)
            let across = context.region.span.latitudeDelta * 111_000
            awayFromPin = centre.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude)) > max(across * 0.15, 25)
        }
        .overlay(alignment: .topTrailing) {
            if interactive {
                VStack(spacing: 0) {
                    Button { satellite.toggle() } label: {
                        Image(systemName: MapModes.styleSymbol).mapControlIcon()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(satellite ? "Standard map" : "Satellite map")
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 0.5)
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) { camera = .region(Self.region(spot, true)) }
                    } label: {
                        Image(systemName: awayFromPin ? "mappin" : "mappin.and.ellipse")
                            .mapControlIcon(tint: awayFromPin ? nil : .green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to the pin")
                }
                .mapGlass(Capsule())
                .padding(10)
            }
        }
        .onChange(of: spot.latitude + spot.longitude) { camera = .region(Self.region(spot, interactive)) }
    }
}
