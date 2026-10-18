//
//  MapLayerSheet.swift
//  shukr
//
//  The map's one sheet (owner, map-one-sheet, 2026-09-29 — "Option A"): while prayer spots or
//  mosques are showing, one sheet stays up. The user drags it between small / medium / large and
//  it keeps that height; a pin tap swaps what's inside with a quick cross-fade instead of closing
//  and reopening a sheet. Every page in it wears the same header (`MapSheetHeader`).
//

import SwiftUI
import MapKit
import SwiftData

/// The sheet's height as it is on screen right now, for the controls that float above it. Its own
/// @Observable so only they re-render while the sheet is dragged, not the whole map screen.
@Observable final class SheetMetrics {
    var height: CGFloat = 0
}

/// Map controls that sit just above the layer sheet (Apple Maps style), or at the bottom when
/// there's none. At the large height they'd be off the top of what's left, so they fade.
struct AboveSheet<Content: View>: View {
    let metrics: SheetMetrics
    let sheetUp: Bool
    @ViewBuilder var content: Content

    var body: some View {
        let h = sheetUp ? metrics.height : 0
        let screen = UIScreen.main.bounds.height
        VStack {
            Spacer()
            content
                .padding(.bottom, h > 0 ? max(h - 20, 0) : 0)   // the sheet stands on the safe area
                .opacity(h > screen * 0.6 ? 0 : 1)
        }
        .animation(.smooth(duration: 0.25), value: h > screen * 0.6)
    }
}

#if DEBUG
/// DEBUG `-logMapFrames YES`: the latest on-screen frame of the sheet and its header parts, printed
/// once things have settled ("MAPFRAME <name> …"), to measure the sheet's alignment.
enum MapFrameLog {
    static var frames: [String: CGRect] = [:]
    static func dump() {
        for (name, r) in frames.sorted(by: { $0.key < $1.key }) {
            print(String(format: "MAPFRAME %@ minY=%.1f maxY=%.1f midY=%.1f minX=%.1f maxX=%.1f", name, r.minY, r.maxY, r.midY, r.minX, r.maxX))
        }
    }
}
#endif

extension View {
    @ViewBuilder func debugMapFrame(_ name: String) -> some View {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "logMapFrames") {
            // In the sheet's own space: global frames go stale while UIKit moves the sheet.
            self.onGeometryChange(for: CGRect.self) { $0.frame(in: .named("mapSheet")) } action: { MapFrameLog.frames[name] = $0 }
        } else { self }
        #else
        self
        #endif
    }
}

/// The sheet is at its small height (set by the map on the whole sheet).
extension EnvironmentValues {
    @Entry var mapSheetCollapsed = false
}

/// The small sheet, for every page in it (owner, map-one-sheet: the prayer bar sat off-centre
/// while the mosques' looked right): the page's own header, alone, centred in the sheet — never
/// the list scrolled to its top. One view for every layer and page, so they can't drift apart.
struct MapSheetCollapsed<Header: View>: View {
    @ViewBuilder var header: Header
    var body: some View {
        header
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .debugMapFrame("collapsed")
    }
}

/// One header for every page in the map's sheet (prayer spots, a cluster, a prayer, mosques, a
/// mosque — owner: "ideally all sheets share the same header look"): an optional ‹ on the left,
/// the title in the app's light rounded type with one quiet line under it, the page's own
/// accessories on the right. No ✕: a layer is left from Explore (owner, D0C2E6DD).
struct MapSheetHeader<Leading: View, Trailing: View>: View {
    var back: (() -> Void)? = nil
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let back {
                MapSheetCircleButton(symbol: "chevron.left", label: "Back", action: back)
            }
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugMapFrame("text")
            trailing
                .debugMapFrame("trailing")
        }
    }
}

extension MapSheetHeader where Leading == EmptyView {
    init(back: (() -> Void)? = nil, title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.init(back: back, title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: trailing)
    }
}

extension MapSheetHeader where Leading == EmptyView, Trailing == EmptyView {
    init(back: (() -> Void)? = nil, title: String, subtitle: String? = nil) {
        self.init(back: back, title: title, subtitle: subtitle, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// The header's round buttons (‹, ☆): 36 pt, a faint fill.
struct MapSheetCircleButton: View {
    let symbol: String
    let label: String
    var tint: Color = .secondary
    var fill: Color = Color.primary.opacity(0.06)
    let action: () -> Void

    var body: some View {
        Button {
            triggerSomeVibration(type: .light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// How the content of the one sheet changes: the old page leaves quickly and the new one comes in
/// a beat later (a plain crossfade ghosted the two).
extension AnyTransition {
    static var layerPage: AnyTransition { .sheetContent(offset: 0) }
}

// MARK: - Prayer spots

/// Prayer spots' filters as one control on the header's right, like the mosques' drive / walk
/// switch (owner, map-one-sheet: the row under the header left an odd gap on the small sheet).
/// The capsule names the range and lights green while anything is filtered; the menu has the
/// five prayers (ticked = shown; unticking the last one shows them all again), the ranges and
/// "Only at a masjid".
struct PrayerFilterMenu: View {
    @ObservedObject var viewModel: LocationViewModel
    let custom: () -> Void

    private let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    private func toggle(_ name: String) {
        triggerSomeVibration(type: .light)
        var names = viewModel.selectedPrayerNames
        if names.contains(name) { names.remove(name) } else { names.insert(name) }
        if names.isEmpty { names = viewModel.defaultPrayerNames }
        withAnimation(.snappy(duration: 0.2)) { viewModel.selectedPrayerNames = names }
    }

    private var rangeTitle: String {
        switch viewModel.quickRange {
        case .allTime: "All time"
        case .thisWeek: "This week"
        case .last30: "30 days"
        case .thisYear: "This year"
        case .lastYear: "12 months"
        case .custom: "Custom"
        }
    }

    var body: some View {
        Menu {
            Section("Prayers") {
                ForEach(order, id: \.self) { name in
                    Button { toggle(name) } label: {
                        if viewModel.selectedPrayerNames.contains(name) {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            }
            Section("When") {
                ForEach(LocationViewModel.QuickRange.allCases) { range in
                    Button {
                        if range == .custom { custom() } else { viewModel.apply(range) }
                    } label: {
                        if viewModel.quickRange == range {
                            Label(range == .custom ? "Custom…" : range.rawValue, systemImage: "checkmark")
                        } else {
                            Text(range == .custom ? "Custom…" : range.rawValue)
                        }
                    }
                }
            }
            Toggle(isOn: $viewModel.onlyAtMasjid) {
                Label("Only at a masjid", systemImage: "building.columns")
            }
        } label: {
            let lit = viewModel.filtersActive
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
                Text(rangeTitle).lineLimit(1)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(lit ? Color.green : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(lit ? Color.green.opacity(0.14) : Color.primary.opacity(0.05)))
            .contentShape(Capsule())
        }
        .menuActionDismissBehavior(.disabled)   // tick several prayers without reopening it
        .accessibilityLabel("Filter prayer spots")
    }
}

/// The prayer-spots sheet's home: the header, the filters, and the prayers on the map right now,
/// newest first by day — the same list idea as the mosques'. A row opens that prayer's page.
struct PrayerSpotsHome: View {
    @ObservedObject var viewModel: LocationViewModel
    let collapsed: Bool
    let custom: () -> Void
    /// The day page's map: no title, no filter — the day's own heading over its prayers (owner, 2026-10-16).
    var dayOnly: Date? = nil

    private var subtitle: String {
        let n = viewModel.visiblePrayerCount
        let count = n == 1 ? "1 in view" : "\(n) in view"
        guard viewModel.filtersActive else { return count }
        let filter = viewModel.filterSentence
            .replacingOccurrences(of: "Showing ", with: "")
            .replacingOccurrences(of: "prayers from ", with: "")
        return "\(count) · \(filter)"
    }

    private var days: [(date: Date, prayers: [PrayerModel])] {
        // The day page's map: the whole day, whatever's in view (opening one prayer zooms in on it; the rest stay
        // listed — Frank's check), under the prayer day it belongs to.
        if let dayOnly {
            let all = viewModel.prayers.sorted { ($0.timeAtComplete ?? $0.startTime) > ($1.timeAtComplete ?? $1.startTime) }
            return all.isEmpty ? [] : [(date: dayOnly, prayers: all)]
        }
        let cal = Calendar.current
        var order: [Date] = []; var byDay: [Date: [PrayerModel]] = [:]
        let newest = viewModel.visiblePrayers
            .sorted { ($0.timeAtComplete ?? $0.startTime) > ($1.timeAtComplete ?? $1.startTime) }
            .prefix(80)
        for p in newest {
            let day = cal.startOfDay(for: p.timeAtComplete ?? p.startTime)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(p)
        }
        return order.map { (date: $0, prayers: byDay[$0] ?? []) }
    }

    private func daySection(_ date: Date, _ prayers: [PrayerModel]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayOnly != nil ? (PrayerDay.todayWord(date) ?? zikrDayLabel(date)) : zikrDayLabel(date))
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(prayers.enumerated()), id: \.offset) { i, prayer in
                    row(prayer)
                    if i < prayers.count - 1 {
                        Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5).padding(.leading, 14)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.primary.opacity(0.045)))
        }
    }

    private func row(_ prayer: PrayerModel) -> some View {
        Button { viewModel.open(prayer) } label: {
            HStack {
                PrayerSpotRow(prayer: prayer)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: The one-day map: where you prayed (owner, 2026-10-17, option A: "the day grouped by place")

    /// The day's prayers on the map, Fajr → Isha.
    private var onMap: [PrayerModel] {
        viewModel.prayers.filter { $0.isCompleted && DayFacts.spot($0) != nil }
            .sorted { (JourneyLog.names.firstIndex(of: $0.name) ?? 9) < (JourneyLog.names.firstIndex(of: $1.name) ?? 9) }
    }

    /// The day's places, in the order the day reached them: a masjid by its name, else prayers within ~75 m of each
    /// other as one spot.
    private var dayPlaces: [[PrayerModel]] {
        var groups: [[PrayerModel]] = []
        for p in onMap {
            guard let c = DayFacts.spot(p) else { continue }
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if let i = groups.firstIndex(where: { g in
                guard let first = g.first, let f = DayFacts.spot(first) else { return false }
                if let m = p.mosqueName, !m.isEmpty, p.atMasjid { return first.atMasjid && first.mosqueName == m }
                return !first.atMasjid && CLLocation(latitude: f.latitude, longitude: f.longitude).distance(from: here) < 75
            }) {
                groups[i].append(p)
            } else {
                groups.append([p])
            }
        }
        return groups
    }

    /// "Tuesday, Oct 6" ("Today", "Yesterday"); the year when it isn't this one.
    private func dayTitle(_ d: Date) -> String {
        if let word = PrayerDay.todayWord(d) { return word }
        let thisYear = Calendar.current.isDate(d, equalTo: Date(), toGranularity: .year)
        return thisYear ? d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                        : d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    @ViewBuilder private var header: some View {
        if dayOnly != nil {
            // Collapsed, the day itself in the sheet's own title look, as "Prayer spots" is (owner, 2026-10-17: "it should
            // say the date when it's folded. And it should say it nicely, like how the text looks when the sheet is folded
            // in the regular maps"); open, the day section's own label is the heading.
            // Folded or open, the day's own header: its date; "Day 623 · 2 places · 4 prayers"; its score in the fifths
            // ring, top right (owner, 2026-10-17: "show the day's score. On the right side of the sheet, top right. In a
            // ring. Using our fifths. And also in the second line leading it, let's put like day number").
            if let dayOnly {
                let log = JourneyLog.last
                let day = log?.day(dayOnly)
                let n = onMap.count, places = dayPlaces.count
                // No prayer count: the ring's fifths show it (owner: "get rid of how many prayers there are").
                let line = [log?.dayNumber(dayOnly, lifetime: true).map { "Day \($0)" },
                            n == 0 ? nil : places == 1 ? "1 place" : "\(places) places"].compactMap { $0 }.joined(separator: " · ")
                // The date is the biggest thing on the sheet (owner: "the date should be the biggest text on the page").
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayTitle(dayOnly))
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(line)
                            .font(.system(size: 14, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let day, day.active {
                        JourneyDayFifths(day: day, center: "\(day.dayScore)", colored: true).frame(width: 58, height: 58)
                    }
                }
            }
        } else {
            MapSheetHeader(title: "Prayer spots", subtitle: subtitle) {
                PrayerFilterMenu(viewModel: viewModel, custom: custom)
            }
        }
    }

    var body: some View {
        if collapsed {
            MapSheetCollapsed { header }
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // The scroll-to-top target sits above the padding: scrolling the header itself to the
                // top threw the 20 pt top padding away, so the small bar's header sat high with an
                // empty band under it (owner, map-one-sheet — the mosques' bar was fine).
                Color.clear.frame(height: 0).id("top")
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Group {
                    if days.isEmpty {
                        Text(viewModel.prayers.isEmpty
                             ? "Prayers you mark show up here, pinned where you prayed them."
                             : "No prayers in view. Move the map, or change the filters.")
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 24)
                    }
                    if dayOnly != nil {
                        DayBento(places: dayPlaces, day: viewModel.prayers.filter(\.isCompleted), viewModel: viewModel)
                    } else {
                        ForEach(days, id: \.date) { day in
                            daySection(day.date, day.prayers)
                        }
                    }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
        }
        .fontDesign(.rounded)
    }
}


/// The one-day map's sheet: a bento of what the map knows that Journey doesn't (owner, 2026-10-17: "what would it look
/// like if … all the prayers are done at home? … some chips or sections, like a bento box, showing different stats for
/// that day … in the shortcuts, we have the logic for showing how many times we've prayed in an area … Just do whatever
/// you want"). Where (the day's main place, a tap flies there), then one row: prayed here, ever (the "prayed here"
/// shortcut's rule: 100 m, or the same masjid) · masjid · moved.
private struct DayBento: View {
    /// The day's places, the order the day reached them (PrayerSpotsHome.dayPlaces).
    let places: [[PrayerModel]]
    /// The day's marked prayers, on the map or not.
    let day: [PrayerModel]
    @ObservedObject var viewModel: LocationViewModel
    @Environment(\.modelContext) private var context
    /// Each place's name, as it's found (a masjid's own, else the street).
    @State private var names: [Int: String] = [:]
    @State private var history: (count: Int, since: Date?)?
    /// The place picked from the chevron's menu (nil: where most of the day was prayed).
    @State private var picked: Int?

    /// The place the tiles are about: the one picked, else where most of the day was prayed (of equals, the first the day
    /// reached — owner, 2026-10-17: "Why are we only showing one address and which one do we choose to show? … Maybe we
    /// put like a little up and down chevron to change the location").
    private var shown: Int? {
        if let picked, places.indices.contains(picked) { return picked }
        return places.indices.max { places[$0].count < places[$1].count || (places[$0].count == places[$1].count && $0 > $1) }
    }
    private var main: [PrayerModel]? { shown.map { places[$0] } }
    private var mainSpot: CLLocationCoordinate2D? { main?.first.flatMap(DayFacts.spot) }
    private func masjid(_ i: Int) -> String? {
        places[i].first.flatMap { $0.atMasjid ? $0.mosqueName : nil }.flatMap { $0.isEmpty ? nil : $0 }
    }
    private var marked: Int { day.count }

    var body: some View {
        VStack(spacing: 10) {
            if let main {
                Button {
                    guard let c = mainSpot else { return }
                    triggerSomeVibration(type: .light)
                    viewModel.present(PrayerSpotSelection(prayers: main, coordinate: c))
                } label: {
                    tile("Where", shown.flatMap { names[$0] } ?? "Finding the place…",
                         main.count == marked ? (marked == 1 ? "Prayed here" : "All \(marked) prayed here")
                         : "\(main.map(\.displayName).joined(separator: " · ")) · \(places.count - 1) other \(places.count == 2 ? "place" : "places")",
                         big: true)
                }
                .buttonStyle(.plain)
                // The day's other places: the month title's up-down chevron, a menu of them.
                .overlay(alignment: .topTrailing) {
                    if places.count > 1 {
                        Menu {
                            ForEach(places.indices, id: \.self) { i in
                                Button {
                                    triggerSomeVibration(type: .light)
                                    picked = i
                                } label: {
                                    Text(names[i] ?? "Finding the place…")
                                    Text(places[i].map(\.displayName).joined(separator: " · "))
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .tint(.secondary)   // grey, as the month title's chevron (a menu takes the app's tint)
                        .accessibilityLabel("Other places that day")
                    }
                }
            }
            // One row of three (owner: the masjid, how much moved and "how many times you prayed here" stay; the first and
            // last times go — "I don't really agree with the time differential thing").
            HStack(spacing: 8) {
                tile("Prayed here", history.map { "\($0.count)" } ?? "–",
                     history?.since.map { "since \($0.formatted(.dateTime.month(.abbreviated).year()))" } ?? "ever")
                let atMasjid = day.filter(\.atMasjid).count
                tile("Masjid", atMasjid == 0 ? "None" : "\(atMasjid) of \(marked)", atMasjid == 0 ? "that day" : "prayers")
                tile("Moved", moved.value, moved.detail)
            }
        }
        .task(id: shown) { loadHistory() }
        .task(id: places.count) { await loadNames() }
    }

    // MARK: The tiles' words

    /// "One place" all day, else the farthest two places apart.
    private var moved: (value: String, detail: String) {
        let spots = places.compactMap { $0.first.flatMap(DayFacts.spot) }.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var far = 0.0
        for a in spots { for b in spots { far = max(far, a.distance(from: b)) } }
        guard spots.count > 1, far > 75 else { return ("Stayed", "one place") }
        let d = Measurement(value: far, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
        return (d, "between \(places.count) places")
    }

    private func tile(_ title: String, _ value: String, _ detail: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .tracking(1.2).textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: big ? 22 : 19, weight: .light, design: .rounded))
                .lineLimit(big ? 2 : 1).minimumScaleFactor(0.75)
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 13, weight: .light, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(big ? 14 : 12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.045)))
        .contentShape(Rectangle())
    }

    // MARK: Loading

    /// Every prayer ever marked at the day's main place: within 100 m, or anywhere at its masjid (1 km) — one a prayer a
    /// day (PrayedHere's rule, the "How many times have I prayed here" shortcut).
    private func loadHistory() {
        guard let c = mainSpot else { history = nil; return }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(predicate: #Predicate { $0.isCompleted == true }))) ?? []
        func distance(_ r: PrayerModel) -> Double {
            guard let s = DayFacts.spot(r) else { return .infinity }
            return CLLocation(latitude: s.latitude, longitude: s.longitude).distance(from: here)
        }
        var near = rows.filter { distance($0) <= 100 }
        if let i = shown, let m = masjid(i) { near += rows.filter { $0.mosqueName == m && distance($0) <= 1_000 } }
        var seen = Set<String>()
        let unique = near.filter { seen.insert("\($0.dayKey)|\($0.name)").inserted }
        history = (unique.count, unique.map { $0.timeAtComplete ?? $0.startTime }.min())
    }

    /// Every place's name: a masjid's own, else street + city as a pin's page finds it (shared cache on the view model).
    private func loadNames() async {
        for i in places.indices {
            if let m = masjid(i) { names[i] = m; continue }
            guard let c = places[i].first.flatMap(DayFacts.spot) else { continue }
            let key = String(format: "%.4f,%.4f", c.latitude, c.longitude)
            if let cached = viewModel.addressCache[key] { names[i] = cached; continue }
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
            let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let place = [street.isEmpty ? placemark?.name : street, placemark?.locality].compactMap { $0 }.joined(separator: ", ")
            guard !place.isEmpty else { continue }
            viewModel.addressCache[key] = place
            names[i] = place
        }
    }
}
