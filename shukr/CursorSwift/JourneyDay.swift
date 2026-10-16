import SwiftUI
import SwiftData
import CoreLocation
import MapKit

/// A day in Journey, on the Salah tab's day page pieces (the day page merge, owner 2026-10-15; DayPage.swift): the date
/// centred on top, the day's ring (DayRing / DayCentre), the picked prayer's note and place under it, the list card with
/// plain chevrons either side (‹ › walk the days from the first one to yesterday — today only once all five are marked),
/// and the pill that flips the card to the day's Notes · Photos · On the map · Zikr. A row tapped picks its prayer into
/// the ring; held, it opens the prayer's sheet (JourneyPrayerSheet: mark, unmark, the time, the place, the note). A drag
/// sideways moves a day; the left edge stays the system's back.
struct JourneyDayPage: View {
    @State var date: Date
    let firstDay: Date?
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var viewModel: PrayerViewModel
    @State private var sheetRow: PrayerModel?
    @State private var rows: [PrayerModel] = []
    @State private var facts = DayFacts()
    @State private var picked: Int?
    @State private var flipped = false
    @State private var notesOpen = false
    @State private var noteShown = false
    @State private var placeSheet: PrayerModel?
    @State private var showMap = false
    @State private var zikrDay: Date?
    @State private var showMakeUp = false
    @State private var makeUpCount: Int?
    /// A photo's day pile, opened over Moments (owner: a photo here opens the pile for that day).
    @State private var pile: JourneyPileRoute?
    @State private var places = 0   // bumps as place names arrive

    private var today: Date { PrayerDay.start() }
    #if DEBUG
    @MainActor private static var demoSheetDone = false
    #endif
    private var canGoBack: Bool { firstDay.map { date > $0 } ?? false }
    /// Forward to today only once it's over — all five marked: the day page never shows live rows (owner).
    private var canGoForward: Bool {
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: date), next <= today else { return false }
        if next < today { return true }
        let t = viewModel.todaysPrayers
        return t.count == 5 && t.allSatisfy(\.isCompleted)
    }
    /// Every prayer excused and none marked: the card keeps its size, a symbol and a line in it (ExcusedDayCard).
    private var excusedDay: Bool {
        guard !rows.isEmpty, rows.allSatisfy({ !$0.isCompleted }) else { return false }
        let ranges = Excused.ranges
        return rows.allSatisfy { Excused.covers(start: $0.startTime, end: $0.endTime, in: ranges) }
    }
    /// The picked prayer's row.
    private var pickedRow: PrayerModel? {
        guard let i = picked, DayRing.order.indices.contains(i) else { return nil }
        return rows.first { $0.name == DayRing.order[i] }
    }
    /// "5:31 PM · On time · 83", under the note on its card.
    private var pickedLine: String {
        guard let row = pickedRow else { return "" }
        return [row.timeAtComplete.map { $0.formatted(date: .omitted, time: .shortened) }, row.scoreSummary].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let _ = places
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        // Sideways: the days (the left ~20 pt edge is the system's back swipe, which wins there).
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            let w = v.translation.width, h = v.translation.height
            guard abs(w) > 50, abs(w) > abs(h) * 1.5 else { return }
            step(w < 0 ? 1 : -1)
        })
        .navigationDestination(item: $zikrDay) { ZikrDaySessionsPage(date: $0) }
        // Pushed without a slide: the pile fades in over the page and, closed, takes Moments with it.
        .navigationDestination(item: $pile) { MemoriesPage(openPile: $0.key, leaveWithPile: true) }
        .navigationDestination(isPresented: $showMakeUp) { JourneyMakeUpPage(month: JourneyLog.monthStart(date)) }
        .sheet(item: $sheetRow, onDismiss: load) { row in
            JourneyPrayerSheet(prayer: row)
                .environmentObject(viewModel)
                .environment(\.circleTheme, theme)
        }
        .sheet(isPresented: $showMap) {
            JourneyDayMapSheet(title: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), pins: facts.pins)
        }
        .sheet(item: $placeSheet) { row in
            if let spot = DayFacts.spot(row) {
                PrayerPlaceMapSheet(caption: "\(row.displayName) · \(row.timeAtComplete.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")",
                                    place: DayFacts.place(row) ?? "", spot: spot, score: row.numberScore, atMasjid: row.atMasjid)
            }
        }
        // The note's card (Settings' ⓘ way, grey).
        .infoModal(isPresented: $noteShown, title: pickedRow?.displayName ?? "",
                   symbol: prayerIcon(for: pickedRow?.name ?? "Fajr"), tint: .secondary) {
            DayNoteInfo(text: pickedRow.flatMap(DayFacts.note) ?? "", line: pickedLine)
        }
        .task { load() }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: SessionDeletion.changed)) { _ in load() }   // the back's Zikr row
        // A missed prayer picked: how many are owed, for its pill.
        .onChange(of: picked) { _, i in
            guard let i, DayRing.order.indices.contains(i),
                  let p = dayPrayers.first(where: { $0.name == DayRing.order[i] }), p.missed else { return }
            makeUpCount = JourneyMakeUpPage.entries(context).open.count
        }
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

    private var content: some View {
        VStack(spacing: 0) {
            heading.padding(.top, 2)
            ring.padding(.top, 18)
            // Fixed room under the ring, so the card never moves as the lines come and go (a frame on an EmptyView is
            // nothing: the room is a clear box the lines sit in).
            Color.clear.frame(height: 48).overlay { underRing }.padding(.top, 8)
            cardRow.padding(.top, 6)
            DayFlipPill(flipped: flipped) {
                withAnimation(CircleMotion.dayFlip) { flipped.toggle() }
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil }   // never the same photo twice
            }
            .padding(.top, 16)
            .opacity(facts.isEmpty ? 0 : 1)   // no pill when the back is empty (owner)
            .allowsHitTesting(!facts.isEmpty)
            .animation(.easeOut(duration: CircleMotion.quick), value: facts.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func step(_ by: Int) {
        guard by < 0 ? canGoBack : canGoForward,
              let next = Calendar.current.date(byAdding: .day, value: by, to: date) else { return }
        triggerSomeVibration(type: .light)
        // At once, rows and all (owner's rule: out, then in — a fade left the two days' words over each other).
        picked = nil
        flipped = false
        notesOpen = false
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
        facts = DayFacts.load(rows: rows, day: date, context: context) { places += 1 }
    }

    /// For the ring (DayRing finds its fifths by the five names: a Jumu'ah row is Dhuhr's).
    private var dayPrayers: [DayPrayer] { rows.map(DayPrayer.init) }

    // MARK: Heading

    /// Centred (owner, 2026-10-15): the date, then "8 days ago · Jumada I 3".
    private var heading: some View {
        VStack(spacing: 4) {
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 26, weight: .light, design: .rounded))
            Text(subtitle)
                .font(.system(size: 15, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .contentTransition(.opacity)
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
            NeuRaised(shape: Circle(), radius: 9, offset: 4.5).frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
            DayRing(day: day, picked: picked) { i in
                guard !flipped else { return }   // no pick while the back is up (its pile would double the photo)
                triggerSomeVibration(type: .light)
                withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = picked == i ? nil : i }
            }
            if marked == 0 && picked == nil {
                Text(rows.isEmpty ? "No prayers\nthat day" : excusedDay ? "Excused" : "Nothing marked")
                    .multilineTextAlignment(.center)
                    .font(.system(size: excusedDay ? 30 : 15, weight: .light, design: .rounded))
                    .foregroundStyle(excusedDay ? .primary : .secondary)
            } else {
                DayCentre(day: day, score: PrayerScoring.dayScore(for: rows), picked: picked, yesterday: false,
                          makeUpCount: makeUpCount, onMakeUp: { showMakeUp = true })
                    .animation(.easeOut(duration: CircleMotion.quick), value: picked)
                    .allowsHitTesting(picked != nil)
            }
        }
        .frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
    }

    /// The picked prayer's note and place, each a door (DayPickLines); nothing otherwise.
    @ViewBuilder private var underRing: some View {
        if let row = pickedRow, DayFacts.note(row) != nil || DayFacts.place(row) != nil {
            DayPickLines(note: DayFacts.note(row), place: DayFacts.place(row),
                         onNote: { noteShown = true }, onPlace: { placeSheet = row })
                .transition(.opacity)
        }
    }

    // MARK: The card

    /// The list card between two plain chevrons (owner: "just use plain chevrons … we don't want to overdo the soft
    /// ring look"), flipping to the back (DayFlipCard / DayBackCard) as the Salah tab's does.
    private var cardRow: some View {
        HStack(spacing: 2) {
            chevron("chevron.left", enabled: canGoBack, label: "Previous day") { step(-1) }
            // Each face carries the card's surface, so the whole card turns (Bradley's review).
            DayFlipCard(angle: flipped ? 180 : 0) {
                prayerRows.modifier(SalahLookCard(raised: true))
            } back: {
                DayBackCard(facts: facts, notesOpen: $notesOpen,
                            onPhotos: {
                                guard let first = facts.photoKeys.first else { return }
                                var quiet = Transaction()
                                quiet.disablesAnimations = true
                                withTransaction(quiet) { pile = JourneyPileRoute(key: first) }
                            },
                            onMap: { showMap = true },
                            onZikr: { zikrDay = date })
                    .modifier(SalahLookCard(raised: true))
            }
            chevron("chevron.right", enabled: canGoForward, label: "Next day") { step(1) }
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.25))
                .frame(width: 28, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var prayerRows: some View {
        let ranges = Excused.ranges
        return VStack(spacing: 0) {
            if excusedDay {
                ExcusedDayCard(line: "Excused that day")
            } else if rows.isEmpty {
                Text("shukr wasn't opened that day, so there are no prayer times to show.")
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(height: SalahLook.raisedRowHeight * 5)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let i = DayRing.order.firstIndex(of: row.name)
                    JourneyPrayerRow(row: row, excused: !row.isCompleted && Excused.covers(start: row.startTime, end: row.endTime, in: ranges),
                                     picked: picked != nil && picked == i, last: index == rows.count - 1)
                        .contentShape(Rectangle())
                        // Hold: the prayer's sheet (a prayer that has started); tap: the pick. Exclusive, as the Salah
                        // tab's rows (PrayerButton.rowGesture).
                        .gesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .exclusively(before: TapGesture())
                                .onEnded { value in
                                    switch value {
                                    case .first:
                                        guard row.startTime <= Date() else { return }
                                        triggerSomeVibration(type: .light)
                                        sheetRow = row
                                    case .second:
                                        guard let i, !flipped else { return }
                                        triggerSomeVibration(type: .light)
                                        withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = picked == i ? nil : i }
                                    }
                                }
                        )
                        .accessibilityAction(named: "Open") { sheetRow = row }
                }
            }
        }
    }
}

/// A row of the day's card: the dot in its grade's colour (hollow when not prayed; a pause mark when excused), the name,
/// the time prayed with the grade and score under it (the Salah tab's day page rows). A picked row is a touch raised.
private struct JourneyPrayerRow: View {
    let row: PrayerModel
    let excused: Bool
    let picked: Bool
    let last: Bool

    var body: some View {
        let score = row.isCompleted ? row.numberScore : nil
        HStack(spacing: 12) {
            Group {
                if let score {
                    Circle().fill(PrayerScoring.color(for: score))
                } else if excused {
                    Image(systemName: "pause.circle").font(.system(size: 11, weight: .light)).foregroundStyle(.secondary)
                } else {
                    Circle().strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.3)
                }
            }
            .frame(width: 12, height: 12)
            Text(row.displayName)
                .font(.system(size: 17, weight: .light, design: .rounded))
                .foregroundStyle(row.isCompleted ? .primary : .secondary)
            if row.atMasjid {
                Image(systemName: "building.columns").font(.system(size: 11, weight: .light)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(line)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
                if let summary = row.scoreSummary, row.isCompleted {
                    Text(summary)
                        .font(.caption2).fontWeight(.light)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: SalahLook.raisedRowHeight)
        .background {
            if picked {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 20) }
        }
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        if let at = row.timeAtComplete, row.isCompleted { return time(at) }
        if excused { return "Excused" }
        if row.endTime > Date() { return "Until \(time(row.endTime))" }
        return "Missed"
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
