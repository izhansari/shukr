import SwiftUI
import SwiftData
import CoreLocation
import MapKit

/// A day in Journey (spec screen 2, mock-up Day5): the day's ring for any day (DayRing, as the Salah page's day page), its
/// score and "N of 5 in time"; the five prayers (time · place · grade, the photo); the notes; the day's zikr → History
/// filtered to that day. ‹ › walk the days from the first one to today. A row opens its prayer sheet (JourneyPrayerSheet):
/// mark, unmark, set the time, the place, the note.
struct JourneyDayPage: View {
    @State var date: Date
    let firstDay: Date?
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject private var viewModel: PrayerViewModel
    @State private var sheetRow: PrayerModel?
    @State private var rows: [PrayerModel] = []
    @State private var sessions: [SessionDataModel] = []
    @State private var picked: Int?
    @State private var showZikr = false
    @State private var places = 0   // bumps as place names arrive
    @State private var pickToken = 0
    /// A photo's day pile, opened over Moments (owner: a photo here opens the pile for that day).
    @State private var pile: JourneyPileRoute?
    @State private var showMap = false
    /// The day's notes (prayer name, note), read with the rows: a note saved in the sheet leaves the rows as they were, so
    /// reading them in the body never redrew.
    @State private var written: [(String, String)] = []

    private var today: Date { PrayerDay.start() }
    #if DEBUG
    @MainActor private static var demoSheetDone = false
    #endif
    private var canGoBack: Bool { firstDay.map { date > $0 } ?? false }
    private var canGoForward: Bool { date < today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heading
                ring.frame(maxWidth: .infinity).padding(.top, 22)
                prayerRows.padding(.top, 26)
                notes
                links
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!canGoBack).accessibilityLabel("Previous day")
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward).accessibilityLabel("Next day")
            }
        }
        .navigationDestination(isPresented: $showZikr) { ZikrAreaPage(start: .day(date)) }
        // Pushed without a slide: the pile fades in over the page and, closed, takes Moments with it.
        .navigationDestination(item: $pile) { MemoriesPage(openPile: $0.key, leaveWithPile: true) }
        .sheet(item: $sheetRow, onDismiss: load) { row in
            JourneyPrayerSheet(prayer: row)
                .environmentObject(viewModel)
                .environment(\.circleTheme, theme)
        }
        .sheet(isPresented: $showMap) {
            JourneyDayMapSheet(title: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), pins: pins)
        }
        .task { load() }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in load() }
        #if DEBUG
        .task {
            // -demoJourneySheet N: the day's Nth prayer's sheet (0 = Fajr), once per launch.
            let args = ProcessInfo.processInfo.arguments
            guard !Self.demoSheetDone, let i = args.firstIndex(of: "-demoJourneySheet"), args.indices.contains(i + 1),
                  let n = Int(args[i + 1]) else { return }
            Self.demoSheetDone = true
            try? await Task.sleep(for: .seconds(0.6))
            sheetRow = rows.first { $0.name == JourneyLog.names[min(max(n, 0), 4)] }
        }
        #endif
    }

    private func step(_ by: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: by, to: date) else { return }
        triggerSomeVibration(type: .light)
        // At once, rows and all (owner's rule: out, then in — a fade left the two days' words over each other).
        picked = nil
        date = next
        load()
    }

    // MARK: Data

    private var key: String { PrayerNotificationID.dayKey(date) }

    private func load() {
        let all = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: date)))) ?? []
        let mine = all.filter { $0.dayKey == key && JourneyLog.names.contains($0.name) }
        // One per prayer, a completed row winning.
        var kept: [String: PrayerModel] = [:]
        for row in mine where !(kept[row.name]?.isCompleted ?? false) || row.isCompleted { kept[row.name] = row }
        rows = JourneyLog.names.compactMap { kept[$0] }
        written = rows.compactMap { row in
            guard row.isCompleted, let text = PrayerPhotos.note(PrayerPhotos.key(dayKey: row.dayKey, name: row.name)) else { return nil }
            return (row.displayName, text)
        }
        // The day's zikr: sessions whose prayer day is this one.
        let from = date.addingTimeInterval(-86_400), to = date.addingTimeInterval(2 * 86_400)
        let near = (try? context.fetch(FetchDescriptor<SessionDataModel>(predicate: #Predicate { $0.startTime >= from && $0.startTime < to }))) ?? []
        sessions = near.filter { PrayerDay.start(for: $0.startTime) == date }.sorted { $0.startTime < $1.startTime }
        let spots = rows.compactMap(spot)
        PrayerPlaceNames.fill(spots) { places += 1 }
    }

    private func spot(_ row: PrayerModel) -> CLLocationCoordinate2D? {
        guard let lat = row.latPrayedAt, let lon = row.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// For the ring (DayRing finds its fifths by the five names: a Jumu'ah row is Dhuhr's).
    private var dayPrayers: [DayPrayer] { rows.map(DayPrayer.init) }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 30, weight: .light, design: .rounded))
            Text(subtitle)
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var subtitle: String {
        let back = Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
        let when = back == 0 ? "Today" : back == 1 ? "Yesterday" : back < 14 ? "\(back) days ago"
            : date.formatted(.dateTime.year())
        // The Hijri date at midday (Memories' search uses Umm al-Qura too).
        var hijri = Date.FormatStyle()
        hijri.calendar = Calendar(identifier: .islamicUmmAlQura)
        return "\(when) · \(date.addingTimeInterval(12 * 3600).formatted(hijri.day().month(.wide)))"
    }

    // MARK: The ring

    private var ring: some View {
        let day = dayPrayers
        let marked = rows.filter(\.isCompleted).count
        return ZStack {
            NeuRaised(shape: Circle(), radius: 9, offset: 4.5).frame(width: 222, height: 222)
            DayRing(day: day, picked: picked) { i in
                triggerSomeVibration(type: .light)
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = picked == i ? nil : i }
                pickToken += 1
                let mine = pickToken
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    if pickToken == mine { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil } }
                }
            }
            if marked == 0 && picked == nil {
                Text(rows.isEmpty ? "No prayers\nthat day" : "Nothing marked")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                DayCentre(day: day, score: PrayerScoring.dayScore(for: rows), picked: picked, yesterday: false)
                    .allowsHitTesting(picked != nil)
            }
        }
        .frame(width: 222, height: 222)
    }

    // MARK: The prayers

    private var prayerRows: some View {
        let _ = places
        let ranges = Excused.ranges
        return VStack(spacing: 0) {
            ForEach(rows, id: \.id) { row in
                let excused = !row.isCompleted && Excused.covers(start: row.startTime, end: row.endTime, in: ranges)
                // A prayer that has started opens its sheet (one to come has nothing to mark yet).
                Button {
                    triggerSomeVibration(type: .light)
                    sheetRow = row
                } label: {
                    JourneyPrayerRow(row: row, excused: excused, place: place(row))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.startTime > Date())
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            }
            if rows.isEmpty {
                Text("shukr wasn't opened that day, so there are no prayer times to show.")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
    }

    // MARK: Out of the day: its photos, its map, its zikr

    /// The day's photos as one small pile, its map and its zikr as rows of their own (owner: thumbnails in the rows never
    /// lined up; the map card didn't look right — a link instead).
    private var links: some View {
        let photoKeys = rows.filter(\.isCompleted).map { PrayerPhotos.key(dayKey: $0.dayKey, name: $0.name) }.filter(PrayerPhotos.has)
        let pins = pins
        return VStack(spacing: 0) {
            if !photoKeys.isEmpty {
                linkRow(title: photoKeys.count == 1 ? "1 photo" : "\(photoKeys.count) photos",
                        detail: photoKeys.map { String($0.dropFirst(11)) }.joined(separator: ", ")) {
                    JourneyDayPhotoStack(keys: photoKeys)
                } action: {
                    var quiet = Transaction()
                    quiet.disablesAnimations = true
                    withTransaction(quiet) { pile = JourneyPileRoute(key: photoKeys[0]) }
                }
            }
            if !pins.isEmpty {
                let names = Array(NSOrderedSet(array: rows.compactMap(place))) as? [String] ?? []
                linkRow(title: "On the map",
                        detail: ([pins.count == 1 ? "1 prayer" : "\(pins.count) prayers"] + names.prefix(2)).joined(separator: " · ")) {
                    linkSymbol("map")
                } action: { showMap = true }
            }
            if !sessions.isEmpty {
                let seconds = sessions.reduce(0) { $0 + $1.secondsPassed }
                let names = Array(NSOrderedSet(array: sessions.map { $0.mantra?.name ?? "Freestyle" })) as? [String] ?? []
                linkRow(title: "Zikr · \(ZikrMinutes.text(seconds))",
                        detail: "\(sessions.count) session\(sessions.count == 1 ? "" : "s") · \(names.prefix(3).joined(separator: ", "))") {
                    linkSymbol("circle.hexagonpath")
                } action: { showZikr = true }
            }
        }
        .padding(.top, 18)
    }

    private func linkSymbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
    }

    private func linkRow<Lead: View>(title: String, detail: String, @ViewBuilder lead: () -> Lead,
                                     action: @escaping () -> Void) -> some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            HStack(spacing: 14) {
                lead().frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .light, design: .rounded))
                    Text(detail)
                        .font(.system(size: 13, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Every marked prayer with a spot, as a pin in its grade's colour.
    private var pins: [JourneyDayPin] {
        let _ = places
        return rows.compactMap { row in
            guard row.isCompleted, let at = spot(row) else { return nil }
            return JourneyDayPin(id: row.name, name: row.displayName, spot: at, score: row.numberScore, atMasjid: row.atMasjid)
        }
    }

    private func place(_ row: PrayerModel) -> String? {
        if let m = row.mosqueName, !m.isEmpty { return m }
        return spot(row).flatMap(PrayerPlaceNames.name)
    }

    // MARK: Notes

    @ViewBuilder private var notes: some View {
        if !written.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(written.count == 1 ? "NOTE" : "NOTES")
                    .font(.system(size: 12, design: .rounded)).tracking(0.8).foregroundStyle(.secondary)
                // The prayer's name in its own weight over its note (owner: the thing the note lives under).
                ForEach(written, id: \.0) { name, text in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(text)
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineSpacing(3)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.top, 22)
        }
    }
}

enum ZikrMinutes {
    /// "14 min", "1 hr 5 min", "under a minute".
    static func text(_ seconds: TimeInterval) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 1 { return "under a minute" }
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) hr" : "\(m / 60) hr \(m % 60) min"
    }
}

/// One prayer on a day's page: its dot in its grade colour, the name, when · where (or its window, unmarked), the grade.
/// (Its photo is in the day's pile below — thumbnails here never lined up, owner.)
private struct JourneyPrayerRow: View {
    let row: PrayerModel
    let excused: Bool
    let place: String?

    var body: some View {
        let score = row.isCompleted ? row.numberScore : nil
        HStack(spacing: 12) {
            Group {
                if let score {
                    Circle().fill(PrayerScoring.color(for: score))
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3)
                }
            }
            .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.displayName)
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(row.isCompleted ? .primary : .secondary)
                Text(line)
                    .font(.system(size: 13, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let score {
                Text(row.isJumuah ? "100" : PrayerScoring.grade(for: score) == .perfect ? "Perfect" : PrayerScoring.summary(for: score))
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var photoKey: String { PrayerPhotos.key(dayKey: row.dayKey, name: row.name) }

    private var line: String {
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        if let at = row.timeAtComplete, row.isCompleted {
            return [time(at), place].compactMap { $0 }.joined(separator: " · ")
        }
        if excused { return "Excused" }
        if row.endTime > Date() { return "Until \(time(row.endTime))" }
        return "Not marked · its window was \(time(row.startTime)) – \(time(row.endTime))"
    }
}

struct JourneyPileRoute: Hashable, Identifiable {
    let key: String
    var id: String { key }
}

struct JourneyDayPin: Identifiable {
    let id: String
    let name: String
    let spot: CLLocationCoordinate2D
    let score: Double?
    let atMasjid: Bool
}

/// The day's marked prayers as pins in their grade colours, fitted to them (a little room round a lone pin).
struct JourneyDayMap: View {
    let pins: [JourneyDayPin]
    let interactive: Bool
    @AppStorage(MapModes.satelliteKey) private var satellite = false
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? .all : []) {
            ForEach(pins) { pin in
                Marker(pin.name, systemImage: pin.atMasjid ? "building.columns.fill" : "hands.and.sparkles.fill", coordinate: pin.spot)
                    .tint(PrayerScoring.color(for: pin.score))
            }
        }
        .mapStyle(interactive && satellite ? .hybrid(elevation: .realistic) : .standard(pointsOfInterest: .excludingAll))
        .onAppear { camera = Self.fit(pins) }
        .overlay(alignment: .topTrailing) {
            if interactive {
                VStack(spacing: 0) {
                    Button { satellite.toggle() } label: {
                        Image(systemName: MapModes.globeSymbol(longitude: pins.first?.spot.longitude)).mapControlIcon()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(satellite ? "Standard map" : "Satellite map")
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 0.5)
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) { camera = Self.fit(pins) }
                    } label: {
                        Image(systemName: "mappin.and.ellipse").mapControlIcon()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to the day's prayers")
                }
                .mapGlass(Capsule())
                .padding(10)
            }
        }
    }

    static func fit(_ pins: [JourneyDayPin]) -> MapCameraPosition {
        guard !pins.isEmpty else { return .automatic }
        let lats = pins.map(\.spot.latitude), lons = pins.map(\.spot.longitude)
        let centre = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.006),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.006))
        return .region(MKCoordinateRegion(center: centre, span: span))
    }
}

/// The day's map, full and movable.
struct JourneyDayMapSheet: View {
    let title: String
    let pins: [JourneyDayPin]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            JourneyDayMap(pins: pins, interactive: true)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Done")
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// A day's photos as a small tilted pile (Journey's Moments tile, for one day); still developing ones stay veiled.
struct JourneyDayPhotoStack: View {
    let keys: [String]
    @State private var images: [String: UIImage] = [:]
    private static let lies: [(angle: Double, x: CGFloat, y: CGFloat)] = [(-9, 0, 2), (6, 8, -1), (-2, 14, 1)]

    var body: some View {
        let shown = Array(keys.suffix(3))
        ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.1) { i, key in
                square(key, lie: Self.lies[i + 3 - shown.count])
            }
        }
        .frame(height: 30)
        .task(id: keys) {
            var loaded: [String: UIImage] = [:]
            for key in keys.suffix(3) { if let image = await PrayerPhotos.thumbnail(key) { loaded[key] = image } }
            images = loaded
        }
    }

    private func square(_ key: String, lie: (angle: Double, x: CGFloat, y: CGFloat)) -> some View {
        let corner = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Group {
            if let image = images[key] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.primary.opacity(0.08)
            }
        }
        .frame(width: 26, height: 26)
        .developReveal(key, width: 26, interactive: false)
        .clipShape(corner)
        .overlay(corner.strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
        .rotationEffect(.degrees(lie.angle))
        .offset(x: lie.x, y: lie.y)
    }
}
