import SwiftUI
import SwiftData
import CoreLocation

// The day page (owner, 2026-10-15; spec board/mocks/day-page-merge/spec.md, his words d-261015-ae6c … -5009): the Salah
// tab's end-of-day page and Journey's day page are ONE screen, built from the pieces here and used by both. The ring
// (DayRing / DayCentre, DaySummary.swift) holds the day, or the prayer picked by its fifth or its row; under the ring the
// picked prayer's note and place, each a door; a pill at the bottom flips the list card to its back — the day's Notes,
// Photos, On the map and Zikr rows. Build it once, use it twice (owner: "build it once and use it twice").

/// What the day has beyond its five marks, read once from its rows (both pages): the notes, the photos, the pins, the
/// zikr sessions. `load` is a fetch and a directory listing — call it when the rows change, not in a body.
struct DayFacts {
    struct Note: Identifiable {
        let name: String
        let text: String
        var id: String { name }
    }
    var notes: [Note] = []
    var photoKeys: [String] = []
    /// The prayers those photos are of, as the rows name them ("Jumu'ah" on a Friday, not the key's "Dhuhr").
    var photoNames: [String] = []
    /// Photos of the day developed but still waiting for their tap (PhotoDevelop.needsReveal).
    var developing = 0
    var pins: [JourneyDayPin] = []
    /// The marked prayers with a spot, Fajr → Isha: their names come in as the geocoder answers (`onPlaces`), so they're
    /// read at draw time (`placeNames`), not kept.
    var placedRows: [PrayerModel] = []
    var sessions: [SessionDataModel] = []
    /// The marked prayers' place names, Fajr → Isha, each once.
    @MainActor var placeNames: [String] {
        Array(NSOrderedSet(array: placedRows.compactMap(Self.place))) as? [String] ?? []
    }
    /// Nothing for the back: no pill then (owner: "a row only if it has something; no pill if the whole back is empty").
    var isEmpty: Bool { notes.isEmpty && photoKeys.isEmpty && pins.isEmpty && sessions.isEmpty }

    /// `day` is the prayer day's start (PrayerDay.start); `onPlaces` fires as place names arrive (a redraw then).
    @MainActor static func load(rows: [PrayerModel], day: Date, context: ModelContext,
                                onPlaces: @escaping () -> Void = {}) -> DayFacts {
        var facts = DayFacts()
        let order = JourneyLog.names
        let done = rows.filter(\.isCompleted)
            .sorted { (order.firstIndex(of: $0.name) ?? 9) < (order.firstIndex(of: $1.name) ?? 9) }
        facts.notes = done.compactMap { row in
            PrayerPhotos.note(PrayerPhotos.key(dayKey: row.dayKey, name: row.name)).map { Note(name: row.displayName, text: $0) }
        }
        let withPhoto = done.filter { PrayerPhotos.has(PrayerPhotos.key(dayKey: $0.dayKey, name: $0.name)) }
        let keys = withPhoto.map { PrayerPhotos.key(dayKey: $0.dayKey, name: $0.name) }
        facts.photoKeys = keys
        facts.photoNames = withPhoto.map(\.displayName)
        facts.developing = keys.filter { PhotoDevelop.needsReveal(key: $0) }.count
        facts.pins = done.compactMap { row in
            spot(row).map { JourneyDayPin(id: row.name, name: row.displayName, spot: $0, score: row.numberScore, atMasjid: row.atMasjid) }
        }
        facts.placedRows = done.filter { spot($0) != nil }
        // The day's zikr: sessions whose prayer day is this one.
        let from = day.addingTimeInterval(-86_400), to = day.addingTimeInterval(2 * 86_400)
        let near = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= from && $0.startTime < to }))) ?? []
        facts.sessions = near.filter { PrayerDay.start(for: $0.startTime) == day }.sorted { $0.startTime < $1.startTime }
        PrayerPlaceNames.fill(done.compactMap(spot), onEach: onPlaces)
        return facts
    }

    static func spot(_ row: PrayerModel) -> CLLocationCoordinate2D? {
        guard let lat = row.latPrayedAt, let lon = row.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// The masjid's name, else the place's (once geocoded, PrayerPlaceNames).
    @MainActor static func place(_ row: PrayerModel) -> String? {
        if let m = row.mosqueName, !m.isEmpty { return m }
        return spot(row).flatMap(PrayerPlaceNames.name)
    }

    /// The prayer's note, if one was written.
    static func note(_ row: PrayerModel) -> String? {
        guard row.isCompleted else { return nil }
        return PrayerPhotos.note(PrayerPhotos.key(dayKey: row.dayKey, name: row.name))
    }
}

// MARK: - The rows (one look on both pages)

extension PrayerModel {
    /// A day page row's second line: "Late · 75"; a Jumu'ah "Jumu'ah · 100" — never "Jumu'ah at <masjid>", which ran the
    /// width of the row (owner, 2026-10-16). The masjid stays as the mark by the name and the place under the ring.
    var dayRowSummary: String {
        guard let s = numberScore else { return "" }
        return isJumuah ? "Jumu'ah · \(Int((s * 100).rounded()))" : PrayerScoring.summary(for: s)
    }
}

/// The prayer list's raised band for a row — the prayer on now, a row whose buttons are up, a picked row on the day page.
/// The ONE place the look's raise is drawn: PrayerButton and Journey's rows both use it (owner, 2026-10-16: "selecting a row
/// item should match … how the current prayer looks … raised up … reference that same view logic").
struct SalahRowRaise: View {
    let look: SalahLook
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        switch look {
        case .raised: NeuRaised(shape: Capsule(), radius: 3, offset: 1.5)
        case .prayedOnTap: NeuRaised(shape: Capsule(), radius: 4, offset: 2)
        case .now, .dayNow, .nowLeads, .prayedAt: NeuRaised(shape: shape, radius: 8, offset: 4)
        case .pills, .quiet: NeuPressed(shape: shape)
        case .today, .card, .well, .timeline: Color.clear
        }
    }
}

/// The list's space for the picked row's band: with it, one band glides from row to row (matched geometry) instead of one
/// fading out while another fades in (owner, 2026-10-16: "the transition between selecting one to the other just doesn't
/// feel right"). The Salah list and Journey's card each provide one.
private struct DayPickSpaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var dayPickSpace: Namespace.ID? {
        get { self[DayPickSpaceKey.self] }
        set { self[DayPickSpaceKey.self] = newValue }
    }
}

/// A row's place in the list's pick space (each row is a source; the band goes to the picked one).
struct DayPickAnchor: ViewModifier {
    let name: String
    @Environment(\.dayPickSpace) private var space
    func body(content: Content) -> some View {
        if let space {
            content.matchedGeometryEffect(id: "dayRow." + name, in: space, properties: .frame, isSource: true)
        } else {
            content
        }
    }
}

/// The picked row's raised band: ONE band behind all the rows, moved to the picked row's frame — it glides under the
/// rows it passes, never over them (it was drawn inside the picked row, and later rows covered earlier ones). Goes in the
/// list's background, inside its pick space.
struct DayPickBandLayer: View {
    let picked: String?
    let look: SalahLook
    @Environment(\.dayPickSpace) private var space
    var body: some View {
        if let picked, let space {
            SalahRowRaise(look: look)
                .matchedGeometryEffect(id: "dayRow." + picked, in: space, properties: .frame, isSource: false)
                .transition(.opacity)
        }
    }
}

/// A prayed row's right side on the day page: "@ 7:45 PM" (when it was prayed), the grade and score under it
/// ("Late · 75"). Both pages (owner, 2026-10-16: "should say '@ 7:45PM' to indicate thats the time we prayed it").
struct DayRowTime: View {
    let prayedAt: Date
    let summary: String
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("@ \(shortTimePM(prayedAt))")
                .font(.footnote).fontDesign(.rounded).fontWeight(.light)
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.caption2).fontDesign(.rounded).fontWeight(.light)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .monospacedDigit()
    }
}

/// A row of a past day's card (Journey): the Salah list's row — its dot (the chosen dot style), name in `.callout`
/// light, the day page's time, 44 pt tall in the raised look, raised when picked — drawn from the same pieces as
/// PrayerButton (which only knows today's rows: it marks, it runs the tour).
struct DayCardRow: View {
    let row: PrayerModel
    let excused: Bool
    let picked: Bool
    @Environment(\.circleTheme) private var theme
    @AppStorage(PrayerDotStyle.key) private var dotStyleRaw = PrayerDotStyle.muted.rawValue

    var body: some View {
        HStack {
            PrayerStatusDot(style: PrayerDotStyle(rawValue: dotStyleRaw) ?? .muted,
                            done: row.isCompleted, future: false,
                            scoreColor: row.getColorForPrayerScore(), pulse: 0, excused: excused)
                .frame(width: 24, height: 24, alignment: .leading)
            Text(row.displayName)
                .font(.callout).fontDesign(.rounded).fontWeight(.light)
                // Picked: bright, as the prayer on now is in the list (PrayerButton's emphasisesCurrentRow).
                .foregroundStyle(picked && theme.emphasisesCurrentRow ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary))
            if row.atMasjid {
                Image(systemName: "building.columns").font(.system(size: 11, weight: .light)).foregroundStyle(Color.sage)
            }
            Spacer()
            if row.isCompleted, let at = row.timeAtComplete {
                DayRowTime(prayedAt: at, summary: row.dayRowSummary)
            } else {
                Text(excused ? "Excused" : "Missed")
                    .font(.footnote).fontDesign(.rounded).fontWeight(.light)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, theme.rowVerticalPadding)
        .frame(minHeight: theme.list == .raised ? SalahLook.raisedRowHeight : nil)
        .modifier(DayPickAnchor(name: row.name))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Days changing (Journey)

/// A day in Journey's pager by how far away it is (`away`: 0 on the page, 1 gone): it shrinks and fades as it goes, and
/// grows and brightens as it comes in (owner, 2026-10-16: "as it moves off the page, it fades out and gets a little
/// smaller. And when it comes in, the opposite"; "a little more intense" — subtly).
struct DayPaneMotion: ViewModifier {
    let away: CGFloat
    func body(content: Content) -> some View {
        let d = min(max(away, 0), 1)
        content
            .scaleEffect(1 - 0.1 * d)    // a touch more than the first 6 % (owner: "subtly a little bit more, not dramatically")
            .opacity(1 - 0.75 * d)
    }
}

// MARK: - The flip

/// The list card turning over on its upright axis (owner: "the prayer list card flip around so we see the back of the
/// card"). `angle` 0 = the front, 180 = the back; animate it with CircleMotion.dayFlip. The back is sized to the front
/// (measured), so the card never changes height; whichever face is away takes no taps.
struct DayFlipCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    private let front: Front
    private let back: Back
    @State private var frontHeight: CGFloat = 0
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    init(angle: Double, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.angle = angle
        self.front = front()
        self.back = back()
    }

    var body: some View {
        let showsBack = angle >= 90
        ZStack {
            front
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if abs(frontHeight - $0) > 0.5 { frontHeight = $0 } }
                .opacity(showsBack ? 0 : 1)
                .allowsHitTesting(!showsBack)
                .accessibilityHidden(showsBack)
            // The back is built only once the card starts to turn: unseen, it cost every visit its rows and its photo pile
            // (Frank's hitch test, c240064: the warm rounds grew with each day page opened).
            if angle > 0 {
                back
                    .frame(maxWidth: .infinity)
                    .frame(height: frontHeight > 0 ? frontHeight : nil)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))   // drawn mirrored, so it reads right once turned
                    .opacity(showsBack ? 1 : 0)
                    .allowsHitTesting(showsBack)
                    .accessibilityHidden(!showsBack)
            }
        }
        // No 3D layer at rest: the list is always inside this card on the Salah tab, flipped or not.
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: angle == 0 ? 0 : 0.5)
    }
}

/// The pill that flips the card, where "N photos to develop" sat (owner): one soft pill, the same look as the day page's
/// footer link. The words are placeholders (owner: "not a fan … we can change whenever").
struct DayFlipPill: View {
    let flipped: Bool
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: flipped ? "list.bullet" : "rectangle.2.swap")
                    .font(.system(size: 12, weight: .light))
                Text(flipped ? "Prayers" : "Your day")
                    .font(.system(size: 13, weight: .light, design: .rounded))
            }
            // A step up from the footer link's tertiary (Bradley: it read as disabled): this one does something.
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(NeuRaised(shape: Capsule(), radius: 2.5, offset: 1.2).opacity(0.9))
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(flipped ? "Show the prayers" : "Show the day's notes, photos, map and zikr")
    }
}

// MARK: - The back

/// The back of the list card: the day's rows, each with a grey second line, the same way Journey's day page listed them
/// (owner's picture). Fixed, never scrolling: Notes and Zikr open in the frosted ⓘ card (owner, 2026-10-16: "scrolling on
/// the card is fighting with the page … open the content in a frosted overlay tooltip modal"), Photos the day's pile, the
/// map the day's pins. Rows only for what the day has.
struct DayBackCard: View {
    let facts: DayFacts
    let onNotes: () -> Void
    let onPhotos: () -> Void
    let onMap: () -> Void
    let onZikr: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !facts.notes.isEmpty {
                row(symbol: "text.quote", title: facts.notes.count == 1 ? "Note" : "Notes",
                    detail: facts.notes.map(\.name).joined(separator: ", "), action: onNotes)
            }
            if !facts.photoKeys.isEmpty {
                let n = facts.photoKeys.count
                // "N photos to develop" lives here now (owner): the count waiting for its tap, in the title.
                row(title: (n == 1 ? "1 photo" : "\(n) photos") + (facts.developing > 0 ? " · \(facts.developing) developing" : ""),
                    detail: facts.photoNames.joined(separator: ", "),
                    lead: { JourneyDayPhotoStack(keys: facts.photoKeys) }, action: onPhotos)
            }
            if !facts.pins.isEmpty {
                row(symbol: "map", title: "On the map",
                    detail: ([facts.pins.count == 1 ? "1 prayer" : "\(facts.pins.count) prayers"] + facts.placeNames.prefix(2)).joined(separator: " · "),
                    action: onMap)
            }
            if !facts.sessions.isEmpty {
                let seconds = facts.sessions.reduce(0) { $0 + $1.secondsPassed }
                let names = Array(NSOrderedSet(array: facts.sessions.map { $0.mantra?.name ?? "Freestyle" })) as? [String] ?? []
                row(symbol: "circle.hexagonpath", title: "Zikr · \(ZikrMinutes.text(seconds))",
                    detail: "\(facts.sessions.count) session\(facts.sessions.count == 1 ? "" : "s") · \(names.prefix(3).joined(separator: ", "))",
                    action: onZikr)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        row(title: title, detail: detail, lead: {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
        }, action: action)
    }

    /// A row: its symbol or pile, the title, the grey line, a chevron.
    private func row<Lead: View>(title: String, detail: String, @ViewBuilder lead: () -> Lead,
                                 action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 14) {
                lead().frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .light, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8)   // "5 photos · 5 developing" fits the card's width
                    Text(detail)
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 55)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The day's notes in the frosted ⓘ card: each prayer's name in its own weight over its note (Journey's way).
struct DayNotesInfo: View {
    let notes: [DayFacts.Note]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(note.text)
                        .font(.system(size: 15, weight: .light, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineSpacing(3)
                }
            }
        }
    }
}

/// The day's zikr sessions in the frosted ⓘ card, each drawn with History's own row (SessionRow in its day-card piece),
/// so a change to that row shows here too (owner, 2026-10-16: "use the list item object so that its easy to manage and if
/// we change that list item then it updates and stays consistent here too"). A tap opens the session's page.
struct DaySessionsInfo: View {
    let sessions: [SessionDataModel]
    let onOpen: (SessionDataModel) -> Void
    var body: some View {
        let shown = sessions.sorted { $0.startTime > $1.startTime }
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                SessionRow(session: s, onOpen: { onOpen(s) },
                           rowBackground: AnyView(DayPiece(first: i == 0, last: i == shown.count - 1).padding(.horizontal, -16)),
                           quiet: true)
            }
        }
    }
}

// MARK: - Under the ring

/// The picked prayer's note and place under the ring, whenever it has them (owner: "nothing stays hidden; show a door
/// to get to everything"). The note is one line, cut off; a tap opens the whole note on a frosted card. The place opens
/// the map on that prayer's pin.
struct DayPickLines: View {
    let note: String?
    let place: String?
    let onNote: () -> Void
    let onPlace: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            if let note {
                door(symbol: "text.quote", text: note, action: onNote)
                    .accessibilityLabel("Note: \(note). Opens the whole note.")
            }
            if let place {
                door(symbol: "mappin.and.ellipse", text: place, action: onPlace)
                    .accessibilityLabel("Prayed at \(place). Opens the map.")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func door(symbol: String, text: String, action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .light))
                Text(text).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 14, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The whole note on the frosted card (InfoModal): the note, then one grey line — when it was prayed and its grade.
struct DayNoteInfo: View {
    let text: String
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.system(size: 16, weight: .light, design: .rounded))
                .lineSpacing(3)
            Text(line)
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - In the ring

/// A missed prayer picked: the way to the others still owed (owner, 2026-10-15: "a link to the page saying see the others
/// you gotta make up here"; a basic pill, no sage, not the soft-look pill). Marking stays the list's dot.
struct DayMakeUpPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 4) {
                Text("\(count) to make up")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
            }
            .font(.system(size: 13, weight: .light, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The circle's own tap layer lets taps through while this is in the centre (as for a photo).
        .onAppear { DayPageState.shared.centreAppeared() }
        .onDisappear { DayPageState.shared.centreGone() }
        .accessibilityLabel("\(count) prayers to make up. Opens To make up.")
    }
}

// MARK: - A whole excused day

/// Every prayer of the day excused and none marked: the list card keeps its full size, a symbol at the top and a little
/// copy in it (owner, 2026-10-15: "still show the prayer list in the same size that it would normally be … fill the space
/// with like an SF symbol … with some basic copy").
struct ExcusedDayCard: View {
    /// "You were excused · day 3 of 7" (today), "Excused that day" (Journey).
    let line: String
    var height: CGFloat = SalahLook.raisedRowHeight * 5

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pause.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text(line)
                .font(.system(size: 16, weight: .light, design: .rounded))
            Text("Nothing to mark. The day isn't counted.")
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .combine)
    }
}
