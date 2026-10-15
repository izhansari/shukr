import SwiftUI
import MapKit

// Journey's prayer sheet (phase 2; spec screen 3, mock-ups Sheet5 / Sheet5Mark): one sheet for a marked prayer and an
// unmarked one, on any day. The score ring and one sentence; the window bar with a marker where it was prayed; "Prayed at
// <time> ⌄" opens the wheel in the sheet, and while it's open only the time shows; the place and the moment as two tiles —
// the map grows in place (movable, the pin kept), the photo opens in place (the viewer); the note; Done / Mark + a quiet
// Unmark / Not now. A late mark defaults to now = Qaza (decision journey-past-marks A), editable to any time from the
// prayer's start. Edits keep what the app recorded (`editTime`, `movePrayer`).

extension Notification.Name {
    /// A prayer was marked, unmarked or edited from Journey: its pages read their rows again.
    static let journeyChanged = Notification.Name("journeyChanged")
}

struct JourneyPrayerSheet: View {
    let prayer: PrayerModel
    @EnvironmentObject private var viewModel: PrayerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.circleTheme) private var theme
    @Namespace private var mapSpace

    /// The time being picked (saved with Done / Mark).
    @State private var draft: Date
    @State private var wheelOpen: Bool
    @State private var mapOpen = false
    @State private var pickingSpot = false
    /// A spot picked here, saved with Done / Mark.
    @State private var draftSpot: CLLocationCoordinate2D?
    @State private var editingNote = false
    @State private var noteText = ""
    @State private var note: String?
    @State private var confirmUnmark = false
    @State private var photoTarget: PrayerPhotoTarget?
    @State private var places = 0   // bumps as a place name arrives
    /// The time it opened with (Done saves only a change).
    private let openedWith: Date

    init(prayer: PrayerModel) {
        self.prayer = prayer
        let now = Date()
        // Marked: its time. Unmarked: now — after the window that's made up today, Qaza (owner: the default; another day
        // and time stay behind "Prayed at", never the main choice).
        let start = prayer.timeAtComplete ?? now
        _draft = State(initialValue: start)
        _wheelOpen = State(initialValue: false)
        openedWith = start
        _note = State(initialValue: PrayerPhotos.note(PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name)))
    }

    private var marked: Bool { prayer.isCompleted }
    private var excused: Bool { !marked && Excused.covers(start: prayer.startTime, end: prayer.endTime) }
    private var range: ClosedRange<Date> { prayer.startTime...max(prayer.startTime, Date()) }
    private var score: Double {
        marked && prayer.isJumuah && draftSpot == nil ? 1 : PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draft)
    }
    private var jumuah: Bool { marked && prayer.isJumuah && draftSpot == nil }
    private var photoKey: String { PrayerPhotos.key(dayKey: prayer.dayKey, name: prayer.name) }
    private var savedSpot: CLLocationCoordinate2D? {
        guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    private var shownSpot: CLLocationCoordinate2D? { draftSpot ?? savedSpot }
    private var timeChanged: Bool { abs(draft.timeIntervalSince(openedWith)) >= 30 }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 22).padding(.top, 22)
            ZStack(alignment: .top) {
                if mapOpen, let spot = shownSpot {
                    bigMap(spot)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            scoreRow.padding(.top, 18)
                            timeRow.padding(.top, 18)
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
            if !mapOpen { buttons.padding(.horizontal, 22).padding(.bottom, 8) }
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
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
            Button("Save") { saveNote(noteText) }
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(jumuah ? "Jumu'ah" : prayer.name)
                    .font(.system(size: 28, weight: .light, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                if mapOpen {
                    withAnimation(.easeInOut(duration: 0.35)) { mapOpen = false }
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: mapOpen ? "chevron.down" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primary.opacity(0.07)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mapOpen ? "Close the map" : "Close")
        }
    }

    private var subtitle: String {
        let day = prayer.dayStart.addingTimeInterval(12 * 3600).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        if excused { return "\(day) · excused" }
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
                    Text(excused ? "–" : "\(Int((score * 100).rounded()))")
                        .font(.system(size: 24, weight: .thin, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: score))
                    Text(excused ? "excused" : jumuah ? "Jumu'ah" : PrayerScoring.grade(for: score).rawValue)
                        .font(.system(size: 10, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 78, height: 78)
            .animation(.snappy, value: score)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(excused ? "Excused" : PrayerScoring.summary(for: score))
            VStack(alignment: .leading, spacing: 8) {
                Text(verdict)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: verdict)
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
    }

    /// One plain sentence on what the picked time means (frost, don't scold).
    private var verdict: String {
        if excused { return "You were excused from this prayer, so it isn't due." }
        if jumuah { return "At a masjid on Friday: full marks." }
        let at = shortTimePM(draft)
        switch PrayerScoring.grade(for: score) {
        case .perfect: return "Prayed at \(at), in its first 30 minutes: full marks."
        case .onTime: return "At \(at) it counts in time."
        case .late: return "At \(at), late in its window, it still counts in time."
        case .qaza:
            // Prayed on a later prayer day = made up (To make up's word); later the same day = after its time.
            if PrayerNotificationID.dayKey(PrayerDay.start(for: draft)) > prayer.dayKey {
                let when = Calendar.current.isDateInToday(draft) ? "today" : "on \(draft.formatted(.dateTime.month(.abbreviated).day()))"
                return "Made up \(when), it counts as Qaza."
            }
            return "After its time ended, so it counts as Qaza."
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
                .foregroundStyle(excused || jumuah || madeUpToday ? Color.secondary : Color.sage)
            }
            .padding(.vertical, 14)
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
                .font(.system(size: 14, weight: .light, design: .rounded))
                .foregroundStyle(Color.sage)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Place, moment, note

    private var extras: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                placeTile
                momentTile
            }
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

    private var placeTile: some View {
        tile {
            if let spot = shownSpot {
                JourneyPlaceMap(spot: spot, title: placeTitle, score: excused ? nil : score,
                                atMasjid: draftSpot == nil && prayer.atMasjid, interactive: false)
                    .matchedGeometryEffect(id: "map", in: mapSpace)
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
            } else {
                placeholder("mappin.slash")
            }
        } title: {
            Text(placeTitle)
        } link: {
            Text(shownSpot == nil ? "Add where ›" : "Open the map").foregroundStyle(Color.sage)
        } action: {
            triggerSomeVibration(type: .light)
            if shownSpot == nil {
                pickingSpot = true
            } else {
                withAnimation(.easeInOut(duration: 0.4)) { mapOpen = true }
            }
        }
    }

    @ViewBuilder private var momentTile: some View {
        let _ = PrayerPhotoRevision.shared.value
        let has = PrayerPhotos.has(photoKey)
        // A photo can be taken only while the prayer is on and marked (the camera's rule).
        let canTake = marked && Date() < prayer.endTime
        if has {
            // The photo's own tap opens it in place (the viewer zooms out of it).
            VStack(alignment: .leading, spacing: 8) {
                PrayerPhotoCard(key: photoKey, width: 92)
                    .frame(maxWidth: .infinity)
                    .frame(height: 92)
                tileWords(title: Text("Your photo"), link: Text("Tap to open").foregroundStyle(.secondary))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .frame(maxWidth: .infinity)
        } else {
            tile {
                placeholder(canTake ? "camera" : "camera.badge.ellipsis")
            } title: {
                Text(canTake ? "Add a photo" : "No photo")
            } link: {
                Text(canTake ? "Take one ›" : "Photos are taken during the prayer")
                    .foregroundStyle(canTake ? Color.sage : .secondary)
            } action: {
                guard canTake else { return }
                triggerSomeVibration(type: .light)
                photoTarget = PrayerPhotoTarget.forMarked(prayer)
            }
            .disabled(!canTake)
        }
    }

    private func tile<Top: View>(@ViewBuilder _ top: () -> Top, @ViewBuilder title: () -> Text, @ViewBuilder link: () -> some View,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                top()
                tileWords(title: title(), link: link())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func tileWords(title: Text, link: some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.system(size: 14, weight: .light, design: .rounded)).lineLimit(1)
            link.font(.system(size: 12, weight: .light, design: .rounded)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func placeholder(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .frame(height: 92)
            .overlay(Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(.tertiary))
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
                    .foregroundStyle(note == nil ? Color.sage : .primary.opacity(0.75))
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

    /// A marked prayer's note is written at once; an unmarked one's waits for Mark.
    private func saveNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        note = trimmed.isEmpty ? nil : trimmed
        if marked { PrayerPhotos.setNote(photoKey, note) }
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

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 2) {
            Button(action: primary) {
                Text(excused ? "Excused" : marked ? "Done" : "Mark \(prayer.displayName)")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(excused ? Color.secondary : Color.sage)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Capsule().fill(excused ? Color.primary.opacity(0.06) : Color.sage.opacity(0.16)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(excused)
            Button {
                if marked {
                    triggerSomeVibration(type: .light)
                    // The list's own card (Sami's UnmarkPrompt, with the photo when there is one); another overlay up:
                    // the system alert.
                    if !UnmarkPrompt.ask(for: prayer, onUnmark: unmark) { confirmUnmark = true }
                } else {
                    dismiss()
                }
            } label: {
                Text(marked ? "Unmark \(prayer.displayName)" : "Not now")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func unmark() {
        viewModel.unmarkFromJourney(prayer)
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
        dismiss()
    }

    private func primary() {
        if marked {
            if timeChanged, !jumuah { viewModel.editPrayerTime(prayer, to: draft) }
            if let draftSpot { viewModel.movePrayer(prayer, to: draftSpot) }
        } else {
            let when = min(max(draft, range.lowerBound), Date())
            guard viewModel.markFromJourney(prayer, at: when) else { return }
            if let draftSpot { viewModel.movePrayer(prayer, to: draftSpot) }
            if let note { PrayerPhotos.setNote(photoKey, note) }
        }
        NotificationCenter.default.post(name: .journeyChanged, object: nil)
        dismiss()
    }
}

/// The prayer's spot: small and still on the sheet's tile, or grown and movable (the pin stays; the app map's capsule —
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
            Marker(title, systemImage: atMasjid ? "building.columns.fill" : "hands.and.sparkles.fill", coordinate: spot)
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
                        Image(systemName: MapModes.globeSymbol(longitude: spot.longitude)).mapControlIcon()
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
