import SwiftUI
import SwiftData
import CoreLocation
import MapKit

/// A day in Journey, on the Salah tab's day page pieces (the day page merge, owner 2026-10-15; DayPage.swift): the date in
/// the top bar, then the day (JourneyDayPane: the ring, the picked prayer's lines, the list card and its flip pill) with
/// plain chevrons either side of the card. The days are a pager: the neighbouring day waits just off the edge and comes in
/// under the finger as this one goes out (owner, 2026-10-16: "I want to be able to drag and see the other one coming in as
/// well. Knowing that I'm pulling something in, not just pushing something out"), each fading and shrinking a little with
/// its distance. ‹ › walk the days from the first one to yesterday — today only once all five are marked. The left ~20 pt
/// edge stays the system's back. The doors a day opens (its prayer sheet, the note, the place, the map, the zikr, the
/// pile, To make up) live here, so a day piece only says which.
struct JourneyDayPage: View {
    @State var date: Date
    let firstDay: Date?
    @Environment(\.circleTheme) private var theme
    @EnvironmentObject private var viewModel: PrayerViewModel
    @State private var sheetRow: PrayerModel?
    @State private var noteRow: PrayerModel?
    @State private var placeSheet: PrayerModel?
    /// The back's map: the app's prayer map on that day's prayers only.
    @State private var mapDay: Date?
    @State private var notes: [DayFacts.Note]?
    @State private var zikrDay: Date?
    @State private var showMakeUp = false
    /// The back's Photos: the day's photos as a pile in the photo viewer, over the page.
    @State private var dayPile: DayPileRoute?
    /// The finger's travel sideways (0 at rest); the days sit a page width apart and move with it.
    @State private var dragOffset: CGFloat = 0
    @State private var dragHorizontal: Bool?
    /// The card's back up or not belongs to the page, not to a day: paged while flipped, the next day comes in already
    /// showing its back, never turning as it arrives (owner, 2026-10-16).
    @State private var flipped = false
    /// A Journey transition landing on this page or leaving it (JourneyTransitionLab): how far its own pieces are in.
    @Environment(\.journeyDayEntrance) private var entrance

    private var today: Date { PrayerDay.start() }
    private var pageWidth: CGFloat { UIScreen.main.bounds.width }
    private func day(_ by: Int) -> Date { Calendar.current.date(byAdding: .day, value: by, to: date) ?? date }
    private var canGoBack: Bool { firstDay.map { date > $0 } ?? false }
    /// Forward to today only once it's over — all five marked: the day page never shows live rows (owner).
    private var canGoForward: Bool {
        let next = day(1)
        guard next <= today else { return false }
        if next < today { return true }
        let t = viewModel.todaysPrayers
        return t.count == 5 && t.allSatisfy(\.isCompleted)
    }
    /// Yesterday, this day and tomorrow (the ones that exist), with their place: -1, 0, 1.
    private var shownDays: [(k: Int, date: Date)] {
        [-1, 0, 1].filter { $0 == 0 || ($0 < 0 ? canGoBack : canGoForward) }.map { ($0, day($0)) }
    }

    /// Where a day sits for the finger's travel, and how far "away" it is (0 here … 1 a page off). Side by side, never
    /// overlapping (owner, 2026-10-16: "I don't want overlap … just subtly a little bit more"): the day coming in rides 1:1
    /// under the finger; the day going out moves at 90 % of it, trailing a touch as it leaves. At a full page of travel each
    /// is at its rest, so the hand-over never jumps.
    private func panePlace(_ k: Int) -> (x: CGFloat, away: CGFloat) {
        let w = pageWidth
        let x: CGFloat
        if k == 0 {
            x = dragOffset * 0.9
        } else {
            let incoming = (k > 0 && dragOffset < 0) || (k < 0 && dragOffset > 0)
            x = CGFloat(k) * w + (incoming ? dragOffset : 0)
        }
        return (x, min(abs(x) / w, 1))
    }

    /// The day the top bar names: the neighbour once it's more than half in.
    private var shownDate: Date {
        if dragOffset < -pageWidth / 2 { return day(1) }
        if dragOffset > pageWidth / 2 { return day(-1) }
        return date
    }

    /// The Salah tab's day page geometry (measured on it, raised look, 2026-10-16 — owner: "the spacing of the page
    /// vertically doesn't seem to match"): the ring's disc top 98.7 pt under the top bar's line, 87.3 pt from the disc to the
    /// card (the lines under the ring centred in it), 14 pt from the card to the pill.
    /// From the screen's top edge (the page's content ignores the top safe area, so these are in the Salah page's own
    /// global terms — no measuring of this page's top, which fed back into its own height).
    static let ringTop: CGFloat = 198.7
    static let ringToCard: CGFloat = 87.3
    static let cardToPill: CGFloat = 14

    /// The page's gaps, from the Salah page's own rests (DayPageState.salahRing / salahList / salahPill), so the two match
    /// on every phone; the 17 Pro numbers above until those are known.
    private var layout: JourneyDayLayout {
        let state = DayPageState.shared
        guard let ring = state.salahRing, let list = state.salahList, ring.height > 0, list.height > 0 else {
            return JourneyDayLayout(ringTop: Self.ringTop, ringToCard: Self.ringToCard, cardToPill: Self.cardToPill)
        }
        let discTop = ring.midY - CircleMotion.dayDiscDiameter / 2
        let discBottom = ring.midY + CircleMotion.dayDiscDiameter / 2
        // The pill as measured on the Salah page, else where it sits there: 12 pt above the bottom bar (its footer's padding),
        // its own 31.7 pt tall.
        let pillTop = state.salahPill?.minY ?? state.salahBarTop.map { $0 - 12 - 31.67 }
        let pillGap = pillTop.map { max($0 - list.maxY, 0) } ?? Self.cardToPill
        return JourneyDayLayout(ringTop: max(discTop, 0), ringToCard: max(list.minY - discBottom, 0), cardToPill: pillGap)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keyed by the date, not the slot: the day coming in stays the same piece as it becomes this page's day (keyed by
            // slot it was rebuilt at the swap, and its score, caption and pill flashed — owner).
            ForEach(shownDays, id: \.date) { item in
                let place = panePlace(item.k)
                JourneyDayPane(date: item.date, current: item.k == 0, layout: layout, actions: actions, pageFlipped: flipped) {
                    withAnimation(CircleMotion.dayFlip) { flipped.toggle() }
                }
                    .modifier(DayPaneMotion(away: place.away))
                    .offset(x: place.x)
                    .allowsHitTesting(item.k == 0)
            }
            // The chevrons stay on the page, beside the card (12 pt off it), whatever the days do.
            HStack {
                chevron("chevron.left", enabled: canGoBack, label: "Previous day") { page(-1) }
                Spacer()
                chevron("chevron.right", enabled: canGoForward, label: "Next day") { page(1) }
            }
            .padding(.horizontal, 16)
            .frame(height: SalahLook.raisedRowHeight * 5)
            .padding(.top, layout.ringTop + CircleMotion.dayDiscDiameter + layout.ringToCard)
            .opacity(entrance?.rest ?? 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)   // laid out from the screen's top, as the Salah page's rests are
        .contentShape(Rectangle())
        .gesture(dayDrag)
        .background(theme.surface.opacity(entrance?.page ?? 1).ignoresSafeArea())
        .fontDesign(.rounded)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { heading } }
        .fullScreenCover(item: $dayPile) { route in
            PrayerPhotoViewer(key: route.keys[0], pile: route.keys, from: route.from) {
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { dayPile = nil }
            }
            .presentationBackground(.clear)
        }
        .navigationDestination(isPresented: $showMakeUp) { JourneyMakeUpPage(month: JourneyLog.monthStart(date)) }
        .sheet(item: $sheetRow) { row in
            JourneyPrayerSheet(prayer: row)
                .environmentObject(viewModel)
                .environment(\.circleTheme, theme)
        }
        .fullScreenCover(isPresented: Binding(get: { mapDay != nil }, set: { if !$0 { mapDay = nil } })) {
            LocationMapContentView(dayOnly: mapDay ?? date)
        }
        .sheet(item: $placeSheet) { row in
            if let spot = DayFacts.spot(row) {
                PrayerPlaceMapSheet(caption: "\(row.displayName) · \(row.timeAtComplete.map { $0.formatted(date: .omitted, time: .shortened) } ?? "")",
                                    place: DayFacts.place(row) ?? "", spot: spot, score: row.numberScore, atMasjid: row.atMasjid)
            }
        }
        // The back's Notes in the frosted ⓘ card (owner).
        .infoModal(isPresented: Binding(get: { notes != nil }, set: { if !$0 { notes = nil } }),
                   title: notes?.count == 1 ? "Note" : "Notes", symbol: "text.quote", tint: .secondary) {
            DayNotesInfo(notes: notes ?? [])
        }
        // The back's Zikr: History locked to that day (owner).
        .navigationDestination(item: $zikrDay) { ZikrAreaPage(start: .dayOnly($0)) }
        // The note's card (Settings' ⓘ way, grey).
        .infoModal(isPresented: Binding(get: { noteRow != nil }, set: { if !$0 { noteRow = nil } }),
                   title: noteRow?.displayName ?? "", symbol: prayerIcon(for: noteRow?.name ?? "Fajr"), tint: .secondary) {
            DayNoteInfo(text: noteRow.flatMap(DayFacts.note) ?? "",
                        line: [noteRow?.timeAtComplete.map { $0.formatted(date: .omitted, time: .shortened) }, noteRow?.scoreSummary]
                            .compactMap { $0 }.joined(separator: " · "))
        }
    }

    private var actions: JourneyDayActions {
        JourneyDayActions(
            openSheet: { sheetRow = $0 },
            note: { noteRow = $0 },
            place: { placeSheet = $0 },
            map: { mapDay = $0 },
            notes: { notes = $0 },
            zikr: { zikrDay = $0 },
            pile: { route in
                var quiet = Transaction()
                quiet.disablesAnimations = true   // no slide: the deck zooms out of the row
                withTransaction(quiet) { dayPile = route }
            },
            makeUp: { showMakeUp = true })
    }

    // MARK: Paging

    /// The finger carries the days; let go past a quarter of the width (or with a flick) and the next one settles in on
    /// the day spring, else this one springs back. At the first / latest day it gives a little. A drag that starts on the
    /// left ~20 pt edge is the system's back swipe, not a day.
    private var dayDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                if dragHorizontal == nil {
                    dragHorizontal = v.startLocation.x > 20 && abs(v.translation.width) > abs(v.translation.height)
                }
                guard dragHorizontal == true else { return }
                let w = v.translation.width
                let allowed = w < 0 ? canGoForward : canGoBack
                dragOffset = allowed ? w : w * 0.15
            }
            .onEnded { v in
                defer { dragHorizontal = nil }
                guard dragHorizontal == true else { return }
                let w = v.translation.width, projected = v.predictedEndTranslation.width
                let by = w < 0 ? 1 : -1
                let allowed = by > 0 ? canGoForward : canGoBack
                guard allowed, abs(w) > pageWidth / 4 || abs(projected) > pageWidth / 2 else {
                    withAnimation(CircleMotion.daySlideIn) { dragOffset = 0 }
                    return
                }
                page(by)
            }
    }

    /// The neighbour settles in on the spring; then it becomes this page's day (its piece stays — no reload).
    private func page(_ by: Int) {
        guard by < 0 ? canGoBack : canGoForward else { return }
        triggerSomeVibration(type: .light)
        withAnimation(CircleMotion.daySlideIn) { dragOffset = by > 0 ? -pageWidth : pageWidth } completion: {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                date = day(by)
                dragOffset = 0
            }
        }
    }

    private func chevron(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Plain (no soft ring — owner), but noticeable: a size up, a step brighter than secondary.
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(enabled ? Color.primary.opacity(0.55) : Color.secondary.opacity(0.2))
                .frame(width: 28, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Heading

    /// In the top bar, on the back button's line (owner, 2026-10-16: "sit at the top, like in the top bar … same line as the
    /// back chevron … say relatively to today where we are in time … don't need the Islamic calendar").
    /// Another day: the old title goes out, then the new one comes in (Frank's check: crossfaded, both were drawn over each
    /// other for a frame or two).
    private var heading: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(shownDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                Text(Self.relative(shownDate, to: today))
                    .font(.system(size: 12, weight: .light, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()
            .id(shownDate)
            .transition(CircleMotion.dayPickSwap)
        }
        .opacity(entrance?.rest ?? 1)
        .accessibilityElement(children: .combine)
    }

    /// Where the day sits from today: "Today", "Yesterday", "3 days ago", "a week ago", "3 weeks ago", "a month ago",
    /// "3 months ago", "a year ago", "2 years ago".
    static func relative(_ day: Date, to today: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: day), to: cal.startOfDay(for: today)).day ?? 0
        let months = cal.dateComponents([.month], from: cal.startOfDay(for: day), to: cal.startOfDay(for: today)).month ?? 0
        func ago(_ n: Int, _ unit: String) -> String { n == 1 ? "a \(unit) ago" : "\(n) \(unit)s ago" }
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<31 where months < 1: return ago(days / 7, "week")
        default: return months < 12 ? ago(max(months, 1), "month") : ago(months / 12, "year")
        }
    }
}

/// The day page's vertical gaps (JourneyDayPage.layout).
/// A Journey transition landing on the day page or leaving it (JourneyTransitionLab, 2026-10-16): how far the page's own
/// pieces are in, each 0…1. Nil (the default) is the page as always. The grown ring hands over to `disc` and `drawn`.
struct JourneyDayEntrance: Equatable {
    /// The page's surface (it covers what's under it).
    var page: Double = 1
    /// The raised disc behind the ring.
    var disc: Double = 1
    /// DayRing's draw-in: its grade colours, fifth by fifth.
    var drawn: CGFloat = 1
    /// Everything else: the centre, the lines, the card, the pill, the chevrons, the heading.
    var rest: Double = 1
}

extension EnvironmentValues {
    @Entry var journeyDayEntrance: JourneyDayEntrance? = nil
}

/// Where the current day's disc is on screen and which day it is — a transition into the day page lands on it, and going
/// back leaves from it (the day may have been paged since). Not observed: read when a transition starts or lands.
@MainActor final class JourneyDayRingSpot {
    static let shared = JourneyDayRingSpot()
    private(set) var date: Date?
    private(set) var frame: CGRect = .zero
    private var frames: [Date: CGRect] = [:]
    /// Called when the frame first arrives (a transition waiting to land).
    var onReport: ((Date, CGRect) -> Void)?
    func report(date: Date, frame: CGRect) {
        frames[date] = frame
        self.date = date
        self.frame = frame
        onReport?(date, frame)
    }
    func claim(date: Date) {
        self.date = date
        if let f = frames[date] { frame = f }
    }
}

struct JourneyDayLayout: Equatable {
    let ringTop: CGFloat
    let ringToCard: CGFloat
    let cardToPill: CGFloat
}

/// What a day piece asks its page to open.
struct JourneyDayActions {
    let openSheet: (PrayerModel) -> Void
    let note: (PrayerModel) -> Void
    let place: (PrayerModel) -> Void
    let map: (Date) -> Void
    let notes: ([DayFacts.Note]) -> Void
    let zikr: (Date) -> Void
    let pile: (DayPileRoute) -> Void
    let makeUp: () -> Void
}

/// One day of Journey's pager: the ring (DayRing / DayCentre), the picked prayer's note and place under it, the Salah
/// list's card (DayCardRow rows, the gliding pick band) and the pill that flips it to the day's Notes · Photos · On the
/// map · Zikr. It reads its own day; a pick or a flip is its own and clears once it's no longer the current day.
struct JourneyDayPane: View {
    let date: Date
    /// The day on the page (a neighbour takes no taps; paged away, its pick clears).
    let current: Bool
    let layout: JourneyDayLayout
    let actions: JourneyDayActions
    /// The page's flip (JourneyDayPage.flipped); a day with nothing on its back keeps its front up and shows no pill.
    let pageFlipped: Bool
    let onFlip: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.circleTheme) private var theme
    @State private var rows: [PrayerModel] = []
    @State private var facts = DayFacts()
    @State private var picked: Int?
    @State private var makeUpCount: Int?
    @State private var places = 0   // bumps as place names arrive
    /// The picked row's band glides between rows in this space (DayPickBandLayer).
    @Namespace private var pickSpace
    @Environment(\.journeyDayEntrance) private var entrance
    #if DEBUG
    @MainActor private static var demoSheetDone = false
    #endif

    /// Every prayer excused and none marked: the card keeps its size, a symbol and a line in it (ExcusedDayCard).
    private var excusedDay: Bool {
        guard !rows.isEmpty, rows.allSatisfy({ !$0.isCompleted }) else { return false }
        let ranges = Excused.ranges
        return rows.allSatisfy { Excused.covers(start: $0.startTime, end: $0.endTime, in: ranges) }
    }
    private var pickedRow: PrayerModel? {
        guard let i = picked, DayRing.order.indices.contains(i) else { return nil }
        return rows.first { $0.name == DayRing.order[i] }
    }
    private var flipped: Bool { pageFlipped && !facts.isEmpty }
    /// For the ring (DayRing finds its fifths by the five names: a Jumu'ah row is Dhuhr's).
    private var dayPrayers: [DayPrayer] { rows.map(DayPrayer.init) }

    var body: some View {
        let _ = places
        VStack(spacing: 0) {
            ring.padding(.top, layout.ringTop)
            // The room under the ring: the picked prayer's lines centred in it, so the card never moves.
            Color.clear.frame(height: layout.ringToCard).overlay { underRing.frame(width: 310) }   // the Salah tab's line width
            card.opacity(entrance?.rest ?? 1)
            DayFlipPill(flipped: flipped) {
                // To the back: the pick clears; to the front: a pick made on the back stays, its row raised (owner).
                if !flipped { withAnimation(.easeOut(duration: CircleMotion.quick)) { picked = nil } }
                onFlip()
            }
            .padding(.top, layout.cardToPill)
            .opacity(facts.isEmpty ? 0 : entrance?.rest ?? 1)   // no pill when the back is empty (owner)
            .allowsHitTesting(!facts.isEmpty)
            .animation(.easeOut(duration: CircleMotion.quick), value: facts.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .task { load() }
        .onReceive(NotificationCenter.default.publisher(for: .journeyChanged)) { _ in load() }
        .onReceive(NotificationCenter.default.publisher(for: SessionDeletion.changed)) { _ in load() }   // the back's Zikr row
        // Paged away: nothing picked when it comes back (the flip stays: it's the page's).
        .onChange(of: current) { _, now in
            guard !now else { return }
            picked = nil
        }
        // A missed prayer picked: how many are owed, for its pill.
        .onChange(of: picked) { _, i in
            guard let i, DayRing.order.indices.contains(i),
                  let p = dayPrayers.first(where: { $0.name == DayRing.order[i] }), p.missed else { return }
            let container = context.container
            Task { makeUpCount = await JourneyMakeUpPage.openCount(container: container) }
        }
        #if DEBUG
        .task {
            // -demoJourneySheet N: the day's Nth prayer's sheet (0 = Fajr), once per launch.
            let args = ProcessInfo.processInfo.arguments
            guard current, !Self.demoSheetDone, let i = args.firstIndex(of: "-demoJourneySheet"), args.indices.contains(i + 1),
                  let n = Int(args[i + 1]) else { return }
            Self.demoSheetDone = true
            try? await Task.sleep(for: .seconds(0.6))
            if let row = rows.first(where: { $0.name == JourneyLog.names[min(max(n, 0), 4)] }) { actions.openSheet(row) }
        }
        #endif
    }

    // MARK: Data

    private func load() {
        let key = PrayerNotificationID.dayKey(date)
        let all = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: PrayerDay.rowsPredicate(forDayStarting: date)))) ?? []
        let mine = all.filter { $0.dayKey == key && JourneyLog.names.contains($0.name) }
        // One per prayer, a completed row winning.
        var kept: [String: PrayerModel] = [:]
        for row in mine where !(kept[row.name]?.isCompleted ?? false) || row.isCompleted { kept[row.name] = row }
        rows = JourneyLog.names.compactMap { kept[$0] }
        facts = DayFacts.load(rows: rows, day: date, context: context) { places += 1 }
    }

    // MARK: The ring

    private var ring: some View {
        let day = dayPrayers
        let marked = rows.filter(\.isCompleted).count
        return ZStack {
            NeuRaised(shape: Circle(), radius: 9, offset: 4.5).frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
                .opacity(entrance?.disc ?? 1)
            DayRing(day: day, picked: picked, drawn: entrance?.drawn ?? 1) { i in
                triggerSomeVibration(type: .light)   // on either side of the card (owner)
                withAnimation(CircleMotion.dayPick) { picked = picked == i ? nil : i }
            }
            if marked == 0 && picked == nil {
                Text(rows.isEmpty ? "No prayers\nthat day" : excusedDay ? "Excused" : "Nothing marked")
                    .multilineTextAlignment(.center)
                    .font(.system(size: excusedDay ? 30 : 15, weight: .light, design: .rounded))
                    .foregroundStyle(excusedDay ? .primary : .secondary)
                    .opacity(entrance?.rest ?? 1)
            } else {
                DayCentre(day: day, score: PrayerScoring.dayScore(for: rows), picked: picked, yesterday: false,
                          makeUpCount: makeUpCount, onMakeUp: actions.makeUp)
                    .animation(CircleMotion.dayPick, value: picked)
                    .allowsHitTesting(picked != nil)
                    .opacity(entrance?.rest ?? 1)
            }
        }
        .frame(width: CircleMotion.dayDiscDiameter, height: CircleMotion.dayDiscDiameter)
        // Where the day's disc sits, for a transition that lands on it or leaves from it (the current day only).
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if current { JourneyDayRingSpot.shared.report(date: date, frame: frame) }
        }
        .onChange(of: current) { _, now in if now { JourneyDayRingSpot.shared.claim(date: date) } }
    }

    /// The picked prayer's note and place, each a door (DayPickLines); nothing otherwise.
    @ViewBuilder private var underRing: some View {
        if let row = pickedRow, DayFacts.note(row) != nil || DayFacts.place(row) != nil {
            DayPickLines(note: DayFacts.note(row), place: DayFacts.place(row),
                         onNote: { actions.note(row) }, onPlace: { actions.place(row) })
                .id(row.name)   // another pick is another line: out, then in (never two notes over each other — Frank)
                .transition(CircleMotion.dayPickSwap)
        }
    }

    // MARK: The card

    /// The Salah list's card; the pill fades it to the day's rows (DayFadeCard / DayBackCard) — Journey's alone (owner,
    /// 2026-10-16: "the salah stays simple. the journey one gets extra stuff").
    private var card: some View {
        // One card surface under both faces: only what's on it fades (a surface per face blinked out mid-change).
        DayFadeCard(progress: flipped ? 1 : 0) {
            prayerRows.modifier(SalahListInsets())
                .background { DayPickBandLayer(picked: picked.flatMap { DayRing.order.indices.contains($0) ? DayRing.order[$0] : nil }, look: theme.list) }
                .environment(\.dayPickSpace, pickSpace)
        } back: {
            DayBackCard(facts: facts,
                        onNotes: { actions.notes(facts.notes) },
                        onPhotos: { from in actions.pile(DayPileRoute(keys: facts.photoKeys, from: from)) },
                        onMap: { actions.map(date) },
                        onZikr: { actions.zikr(date) })
        }
        .modifier(SalahLookCard(raised: true))
        .modifier(SalahLookListFrame())   // the Salah list's width (290 in the soft looks): one card shape on both pages
    }

    private var prayerRows: some View {
        let ranges = Excused.ranges
        // The list's own spacing and insets for the look (theme.rowSpacing, SalahListInsets): the Salah tab's card exactly.
        return VStack(spacing: theme.rowSpacing) {
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
                ForEach(rows, id: \.id) { row in
                    let i = DayRing.order.firstIndex(of: row.name)
                    // The Salah list's row (DayCardRow: its dot, type, "@ time", the raise when picked; no separator lines).
                    DayCardRow(row: row, excused: !row.isCompleted && Excused.covers(start: row.startTime, end: row.endTime, in: ranges),
                               picked: picked != nil && picked == i)
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
                                        actions.openSheet(row)
                                    case .second:
                                        guard let i, !flipped else { return }
                                        triggerSomeVibration(type: .light)
                                        withAnimation(CircleMotion.dayPick) { picked = picked == i ? nil : i }
                                    }
                                }
                        )
                        .accessibilityAction(named: "Open") { actions.openSheet(row) }
                }
            }
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


struct JourneyDayPin: Identifiable {
    let id: String
    let name: String
    let spot: CLLocationCoordinate2D
    let score: Double?
    let atMasjid: Bool
}

/// A day's photos as a small tilted pile (Journey's Moments tile, for one day); still developing ones stay veiled.
struct JourneyDayPhotoStack: View {
    let keys: [String]
    @State private var images: [String: UIImage] = [:]
    /// The top photo square in its box, the ones under it peeking out a little, tilted — the same box whether the day has one
    /// photo or five (owner, 2026-10-16: "the pile has to be the same size as our sf regardless of 1 or 5 pics"; with one
    /// photo it used to sit 14 pt in, "empty space in the beginning").
    private static let lies: [(angle: Double, x: CGFloat, y: CGFloat)] = [(0, 0, 0), (8, 2, -1), (-8, -2, 1)]
    /// The row's symbols' box (20 pt glyphs), so the pile lines up with the note, the map and the zikr symbols.
    static let box: CGFloat = 24
    private static let side: CGFloat = 20

    var body: some View {
        let shown = Array(keys.suffix(3))
        ZStack {
            // Under ones first; the newest on top.
            ForEach(Array(shown.reversed().enumerated()).reversed(), id: \.element) { depth, key in
                square(key, lie: Self.lies[depth])
            }
        }
        .frame(width: Self.box, height: Self.box)
        .task(id: keys) {
            var loaded: [String: UIImage] = [:]
            for key in keys.suffix(3) { if let image = await PrayerPhotos.thumbnail(key) { loaded[key] = image } }
            images = loaded
        }
    }

    private func square(_ key: String, lie: (angle: Double, x: CGFloat, y: CGFloat)) -> some View {
        let corner = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Group {
            if let image = images[key] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.primary.opacity(0.08)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .developReveal(key, width: Self.side, interactive: false)
        .clipShape(corner)
        .overlay(corner.strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
        .rotationEffect(.degrees(lie.angle))
        .offset(x: lie.x, y: lie.y)
    }
}
