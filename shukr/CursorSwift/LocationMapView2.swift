//
//  LocationMapView2.swift
//  shukr
//  for the map view.
//
//  Created on 2/7/25.
//


import SwiftUI
import MapKit
import CoreLocation
import SwiftData
import Combine

// MARK: - CustomPrayerAnnotation
class CustomPrayerAnnotation: MKPointAnnotation {
    var prayer: PrayerModel?
}

/// The prayer whose page is open in the spot sheet, drawn on its own over any cluster so you see
/// that one prayer on the map (2026-09-26). Never clustered, not tappable.
final class FocusPrayerAnnotation: MKPointAnnotation {
    let prayer: PrayerModel
    init(prayer: PrayerModel, coordinate: CLLocationCoordinate2D) {
        self.prayer = prayer
        super.init()
        self.coordinate = coordinate
    }
}

// MARK: - MeccaAnnotation
class MeccaAnnotation: MKPointAnnotation {
    // Empty subclass to identify Mecca annotation
}

class MeccaMarkerAnnotationView: MKMarkerAnnotationView {
    override var annotation: MKAnnotation? {
        didSet {
            if annotation is MeccaAnnotation {
                glyphText = "🕋"
                markerTintColor = .white
                clusteringIdentifier = nil
            }
        }
    }
}




// MARK: - ViewModel

/// State for the map screen. Location and heading come from the app's own managers
/// (`EnvLocationManager` / `CompassState`); this used to run a second CLLocationManager.
/// Nothing here publishes per pan: the bearing follows the *user's* position, the visible
/// count and the Mecca proximity publish only when they change, so the SwiftUI shell isn't
/// re-rendered while the map moves.
final class LocationViewModel: ObservableObject {
    /// The pin (one prayer) or cluster (several) whose page the prayer-spots sheet shows; nil =
    /// the sheet's home (filters + the prayers in view).
    @Published var selection: PrayerSpotSelection?
    /// The one layer sheet's height (owner, map-one-sheet): small / medium / large, the user's to
    /// drag and kept across pin taps and pages. Editing a prayer sizes it to the page for a while
    /// (`setSpotMode`), then gives the user's height back.
    @Published var sheetDetent: PresentationDetent = .medium
    static let sheetSmall: PresentationDetent = .height(84)
    static let browseDetents: Set<PresentationDetent> = [sheetSmall, .medium, .large]
    /// Where the sheet actually is on screen (for the controls above it and centring pins).
    let sheet = SheetMetrics()
    /// The height to return to after editing a prayer.
    private var browseDetent: PresentationDetent = .medium
    /// A prayer's page (one pin, or one prayer of a cluster) is exactly as tall as what's on it:
    /// the page measures itself (`setPageHeight`) — a fixed height left a gap (owner, 2026-09-26).
    @Published private(set) var pageHeight: CGFloat = 300
    var pageDetent: PresentationDetent { .height(pageHeight) }
    var pageFraction: CGFloat { pageHeight / max(UIScreen.main.bounds.height, 1) }
    /// The page's content changed height: the sheet follows it in one spring, so the page grows
    /// to make room for the wheel as it unfolds (and shrinks with it) instead of snapping to a size
    /// and then swapping content (owner, twice: "still not smooth").
    func setPageHeight(_ h: CGFloat) {
        let h = h.rounded()
        guard abs(h - pageHeight) > 1 else { return }
        let onPage = sheetDetent == pageDetent
        if onPage { leavingDetent = sheetDetent }   // allowed until the move is done, so it animates
        pageHeight = h
        if onPage { withAnimation(Self.sheetSpring) { sheetDetent = pageDetent } }
        let stamp = h
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            if self?.pageHeight == stamp { self?.leavingDetent = nil }
        }
    }
    static let sheetSpring = Animation.smooth(duration: 0.42)
    /// Reverse-geocoded addresses, keyed by rounded coordinate, so a pin is looked up once.
    var addressCache: [String: String] = [:]

    /// The old Explore sheet (unused since the dock; kept so nothing dangles).
    @Published var showExplore = false
    /// A tapped pin / cluster: its page swaps into the sheet that's already up, in place, at the
    /// height the user left it (it used to close the sheet and open another 0.4 s later).
    static let pageSwap = Animation.smooth(duration: 0.3)
    func present(_ new: PrayerSpotSelection) {
        if spotMode != .browse { return }   // editing a prayer: pins are scenery
        withAnimation(Self.pageSwap) { selection = new }
    }
    /// A row in the home list: that prayer's page (its pin is lifted out and centred by the page).
    func open(_ prayer: PrayerModel) {
        guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return }
        present(PrayerSpotSelection(prayers: [prayer], coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
    }
    /// ‹ from a spot's page: back to the home list.
    func closeSpot() {
        withAnimation(Self.pageSwap) { selection = nil }
    }
    /// The prayers pinned inside the visible map, for the home list (published only when the set
    /// changes, not per pan).
    @Published var visiblePrayers: [PrayerModel] = []

    @Published var showPrayers: Bool = false

    // Mosque finder (MosqueFinder.swift)
    @Published var showMosques = false
    @Published var mosques: [MKMapItem] = []
    @Published var mosqueSearching = false
    /// The mosque sheet is one sheet (2026-09-26, owner: tapping a mosque closed the list and
    /// opened another sheet; getting back meant closing it and pressing List again): the list,
    /// with a mosque's page pushed inside it. A pin tap opens the same sheet on that mosque.
    @Published var mosquePath: [MKMapItem] = []
    /// Panned well away from the last search: offer "Search this area".
    @Published var mosqueAreaStale = false
    var lastMosqueSearch: MKCoordinateRegion?
    /// Zoom to fit the results once they arrive (a fresh search, not a pan-and-refresh).
    var fitMosquesWhenFound = false

    /// The mosques' list (the pill): back to the list, no mosque open.
    func openMosqueList() {
        withAnimation(Self.pageSwap) { mosquePath = [] }
    }

    /// A row in the list: its page swaps in inside the same sheet, and the map flies to it
    /// (close enough that it isn't in a cluster) and selects its pin, above the sheet.
    func focusMosque(_ item: MKMapItem) {
        withAnimation(Self.pageSwap) { mosquePath = [item] }
        guard let mapView else { return }
        let spot = MKCoordinateRegion(center: item.placemark.coordinate,
                                      span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))
        mapView.setRegion(spot, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak mapView] in
            guard let mapView, let pin = mapView.annotations.compactMap({ $0 as? MosqueAnnotation }).first(where: { $0.item === item }) else { return }
            mapView.selectAnnotation(pin, animated: true)   // → presentMosque, already on this page
        }
    }

    /// A mosque pin: that mosque's page in the sheet (the list behind its ‹), at the user's height.
    func presentMosque(_ item: MKMapItem) {
        if mosquePath != [item] { withAnimation(Self.pageSwap) { mosquePath = [item] } }
    }

    func searchMosques(in region: MKCoordinateRegion, fit: Bool) {
        mosqueSearching = true
        mosqueAreaStale = false
        lastMosqueSearch = region
        fitMosquesWhenFound = fit
        Task { @MainActor in
            let found = await MosqueSearch.find(in: region)
            mosques = MosqueFavorites.merged(found, in: region)   // + your masajid the search missed
            mosqueSearching = false
        }
    }
    @Published var visiblePrayerCount: Int = 0
    @Published var isAtMecca: Bool = false
    /// Bearing from the user (or, without a fix, the map centre) to the Kaaba: degrees
    /// clockwise from true north. The map is north-up, so this is also the on-screen angle.
    @Published var qiblaBearing: Double = 0

    static let meccaCoordinate = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    // Filters (the sheet edits these; defaults = this year, every prayer)
    let defaultStartDate: Date
    let defaultEndDate: Date
    let defaultPrayerNames: Set<String> = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    @Published var selectedStartDate: Date
    @Published var selectedEndDate: Date
    @Published var selectedPrayerNames: Set<String>
    /// Only prayers prayed at a masjid (MasjidDetector).
    @Published var onlyAtMasjid = false
    var filtersActive: Bool {
        selectedStartDate != defaultStartDate || selectedEndDate != defaultEndDate || selectedPrayerNames != defaultPrayerNames || onlyAtMasjid
    }
    /// Ready-made date ranges for the filter sheet. `custom` = the two pickers.
    enum QuickRange: String, CaseIterable, Identifiable {
        case allTime = "All time", thisWeek = "This week", last30 = "Last 30 days", thisYear = "This year", lastYear = "Last 12 months", custom = "Custom"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .allTime: return "infinity"
            case .thisWeek: return "calendar"
            case .last30: return "30.circle"
            case .thisYear: return "calendar.badge.clock"
            case .lastYear: return "clock.arrow.circlepath"
            case .custom: return "slider.horizontal.3"
            }
        }
        /// Start/end of the range, nil for custom.
        func dates(now: Date = Date()) -> (start: Date, end: Date)? {
            let cal = Calendar.current
            switch self {
            case .allTime: return (.distantPast, now)
            case .thisWeek: return (cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now, now)
            case .last30: return (cal.date(byAdding: .day, value: -30, to: now) ?? now, now)
            case .thisYear: return (cal.dateInterval(of: .year, for: now)?.start ?? now, now)
            case .lastYear: return (cal.date(byAdding: .year, value: -1, to: now) ?? now, now)
            case .custom: return nil
            }
        }
    }
    /// The quick range the current dates match, else custom.
    var quickRange: QuickRange {
        let cal = Calendar.current
        for r in QuickRange.allCases {
            guard let d = r.dates() else { continue }
            let sameStart = r == .allTime ? selectedStartDate == .distantPast : cal.isDate(selectedStartDate, inSameDayAs: d.start)
            if sameStart && cal.isDate(selectedEndDate, inSameDayAs: d.end) { return r }
        }
        return .custom
    }
    func apply(_ range: QuickRange) {
        guard let d = range.dates() else { return }
        selectedStartDate = d.start
        selectedEndDate = d.end
    }

    /// The filter bar's sentence: what the pins on the map are, e.g. "Showing all your prayers",
    /// "Showing Fajr, Isha from the last 30 days", "Showing prayers from Jan 1 – Mar 3".
    var filterSentence: String {
        let order = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
        var names = selectedPrayerNames == defaultPrayerNames
            ? "prayers"
            : order.filter { selectedPrayerNames.contains($0) }.joined(separator: ", ")
        if onlyAtMasjid { names += " at a masjid" }
        let f = Date.FormatStyle().month(.abbreviated).day().year(.twoDigits)
        let when: String
        switch quickRange {
        case .allTime:
            if names == "prayers" { return "Showing all your prayers" }
            if names == "prayers at a masjid" { return "Showing your prayers at a masjid" }
            return "Showing every \(names)"
        case .thisWeek: when = "this week"
        case .last30: when = "the last 30 days"
        case .thisYear: when = "this year"
        case .lastYear: when = "the last 12 months"
        case .custom: when = "\(selectedStartDate.formatted(f)) – \(selectedEndDate.formatted(f))"
        }
        return "Showing \(names) from \(when)"
    }

    /// Every prayer with coordinates (set by the view from its @Query) and the filtered set the
    /// map shows. The coordinator subscribes to `filteredPrayers` and rebuilds its pins once
    /// per change — MapKit clusters and culls them itself from there.
    @Published var prayers: [PrayerModel] = []
    @Published private(set) var filteredPrayers: [PrayerModel] = []

    weak var mapView: MKMapView?

    /// Redraw the pins after a prayer changed in place (moved, or its time — and so its colour):
    /// the rows are the same objects, so the @Query doesn't notice.
    func refreshPins() { prayers = prayers }

    // MARK: A prayer's page, and moving its pin (2026-09-26)

    /// The prayer whose page is open: its own pin, lifted out of any cluster.
    private var focusAnnotation: FocusPrayerAnnotation?
    func focus(on prayer: PrayerModel, sheetFraction: CGFloat) {
        guard let mapView, let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return }
        let spot = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if let old = focusAnnotation {
            if old.prayer === prayer, old.coordinate.latitude == lat, old.coordinate.longitude == lon { return }
            mapView.removeAnnotation(old)
        }
        let a = FocusPrayerAnnotation(prayer: prayer, coordinate: spot)
        focusAnnotation = a
        mapView.addAnnotation(a)
        centreFocus()
    }

    /// Where the page's pin sits best: the middle of the map above the sheet.
    private func focusTarget(in mapView: MKMapView) -> CGPoint {
        CGPoint(x: mapView.bounds.midX, y: (130 + mapView.bounds.height - shownSheetHeight - 40) / 2)
    }
    /// The sheet's height for placing pins above it: measured, or a half-screen guess before the
    /// first measurement; a large sheet leaves no map, so pins go where the medium one would.
    var shownSheetHeight: CGFloat {
        let screen = mapView?.bounds.height ?? UIScreen.main.bounds.height
        let h = sheet.height > 0 ? sheet.height : screen * 0.5
        return min(h, screen * 0.5)
    }
    /// Put the page's pin back in view (also the "Back to …" button after panning away).
    func centreFocus() {
        guard let mapView, let a = focusAnnotation else { return }
        let bounds = mapView.bounds
        let point = mapView.convert(a.coordinate, toPointTo: mapView)
        let target = focusTarget(in: mapView)
        if focusDrifted { focusDrifted = false }
        guard hypot(point.x - target.x, point.y - target.y) > 2 else { return }
        let centre = CGPoint(x: bounds.midX + (point.x - target.x), y: bounds.midY + (point.y - target.y))
        mapView.setCenter(mapView.convert(centre, toCoordinateFrom: mapView), animated: true)
    }
    /// The page's pin was panned well away (or off screen): offer to go back to it.
    @Published private(set) var focusDrifted = false
    var focusName: String? { focusAnnotation?.prayer.displayName }
    func checkFocusDrift() {
        guard let mapView, let a = focusAnnotation, spotMode == .browse else {
            if focusDrifted { focusDrifted = false }
            return
        }
        let p = mapView.convert(a.coordinate, toPointTo: mapView)
        let t = focusTarget(in: mapView)
        let drifted = hypot(p.x - t.x, p.y - t.y) > 90
        if drifted != focusDrifted { focusDrifted = drifted }
    }
    func clearFocus(_ prayer: PrayerModel? = nil) {
        guard let a = focusAnnotation, prayer == nil || a.prayer === prayer else { return }
        mapView?.removeAnnotation(a)
        focusAnnotation = nil
        if focusDrifted { focusDrifted = false }
    }

    /// Editing a prayer on its page (2026-09-26, owner: "use the existing sheet space"). The sheet
    /// stays up the whole time and only changes size: `.editTime` shows the wheel; `.pickSpot` turns
    /// the map above it into the picker (a pin fixed in the visible part of the map, `MapPickOverlay`)
    /// with the address / distance card inside the sheet.
    enum SpotSheetMode { case browse, editTime, pickSpot }
    /// What the page shows. The sheet's height always follows the page's content (`setPageHeight`).
    @Published private(set) var spotMode: SpotSheetMode = .browse
    /// The size being left, kept allowed while the sheet moves so it animates instead of snapping.
    private var leavingDetent: PresentationDetent?
    /// Picking: roughly the card's height, for where the pin stands (the middle of the map above).
    static let pickHeight: CGFloat = 190
    var spotDetents: Set<PresentationDetent> {
        var set: Set<PresentationDetent> = switch spotMode {
        case .browse: Self.browseDetents
        case .editTime: [pageDetent]
        case .pickSpot: [pageDetent, .large]          // .large while typing an address
        }
        if let leavingDetent { set.insert(leavingDetent) }
        return set
    }
    /// The map stays usable under the sheet while browsing (up to half) and while picking (the
    /// map is the picker); editing the time dims it. "Up through" needs its detent in the set.
    var spotBackground: PresentationBackgroundInteraction {
        switch spotMode {
        case .browse: .enabled(upThrough: .medium)
        case .editTime: .disabled
        case .pickSpot: .enabled(upThrough: pageDetent)
        }
    }
    func setSpotMode(_ mode: SpotSheetMode) {
        if mode != .pickSpot { hidePickPin(); movingPrayer = nil }
        guard mode != spotMode else { return }
        // Editing sizes the sheet to the page; back to browsing returns the user's height.
        if spotMode == .browse { browseDetent = sheetDetent }
        let leaving = sheetDetent
        leavingDetent = leaving
        withAnimation(Self.sheetSpring) {
            spotMode = mode
            sheetDetent = mode == .browse ? browseDetent : pageDetent
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            if self?.leavingDetent == leaving { self?.leavingDetent = nil }
        }
    }

    /// The prayer whose spot is being picked (the map's chrome steps aside for the picker).
    @Published private(set) var movingPrayer: PrayerModel?
    let pick = SpotPickState()

    /// Start picking: the map flies so `spot` sits under the pin, in the middle of the map above
    /// the sheet (not the screen's middle, which is behind the sheet's edge).
    func startPicking(_ prayer: PrayerModel, at spot: CLLocationCoordinate2D, recorded: CLLocationCoordinate2D?) {
        guard let mapView else { return }
        clearFocus()
        let h = mapView.bounds.height
        pick.pinPoint = CGPoint(x: mapView.bounds.midX, y: (110 + h - Self.pickHeight) / 2)
        pick.original = spot
        pick.recorded = recorded ?? spot
        pick.centre = spot
        pick.moving = false
        setSpotMode(.pickSpot)
        movingPrayer = prayer
        showPickPin()
        jumpPick(to: spot)
    }

    /// The pin is drawn inside the map view itself, at exactly the point the spot is read from —
    /// the SwiftUI overlay sat ~35 pt below it on screen, so the pin and the address disagreed
    /// (owner, 2026-09-26).
    private var pickPin: PickPinView?
    private func showPickPin() {
        guard let mapView else { return }
        pickPin?.removeFromSuperview()
        let pin = PickPinView(tip: pick.pinPoint)
        mapView.addSubview(pin)
        pickPin = pin
        pin.alpha = 0
        UIView.animate(withDuration: 0.25) { pin.alpha = 1 }
    }
    private func hidePickPin() {
        guard let pin = pickPin else { return }
        pickPin = nil
        UIView.animate(withDuration: 0.2, animations: { pin.alpha = 0 }) { _ in pin.removeFromSuperview() }
    }
    func liftPickPin(_ lifted: Bool) { pickPin?.setLifted(lifted) }

    /// Fly the picking map so `spot` lands under the pin: padding the bottom puts the middle of
    /// what's left at the pin's height.
    func jumpPick(to spot: CLLocationCoordinate2D) {
        guard let mapView else { return }
        let h = mapView.bounds.height
        let size = MKMapPointsPerMeterAtLatitude(spot.latitude) * 300
        let p = MKMapPoint(spot)
        let rect = MKMapRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        // MapKit adds the view's safe area to the padding, so take it back out.
        let safe = mapView.safeAreaInsets
        let bottom = h - 2 * pick.pinPoint.y + safe.top - safe.bottom
        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 0, left: 0, bottom: max(bottom, 0), right: 0), animated: true)
    }

    /// Where the pin points on the map right now.
    func pickedCoordinate(on mapView: MKMapView) -> CLLocationCoordinate2D {
        mapView.convert(pick.pinPoint, toCoordinateFrom: mapView)
    }

    func stopPicking() {
        setSpotMode(.editTime)
    }

    /// Turn the map back to north-up (browsing pins / mosques).
    func resetMapHeading() {
        guard let mapView, let camera = mapView.camera.copy() as? MKMapCamera else { return }
        camera.heading = 0
        mapView.setCamera(camera, animated: true)
    }

    /// Qibla-up (owner, 2026-09-26): turn the map so the green line to the Kaaba points straight
    /// up the screen. Hold the phone in front of you, turn until the streets match, and the top
    /// of the phone is the qibla — no arrow pointing one way while the phone points another.
    /// Optionally re-centres on `centre` in the same camera move.
    func pointQiblaUp(centre: CLLocationCoordinate2D? = nil, animated: Bool = true) {
        guard let mapView, let camera = mapView.camera.copy() as? MKMapCamera else { return }
        let origin = centre ?? mapView.userLocation.location?.coordinate ?? mapView.centerCoordinate
        camera.heading = Self.bearingToMecca(from: origin)
        if let centre { camera.centerCoordinate = centre }
        mapView.setCamera(camera, animated: animated)
    }
    /// Qibla mode's home button (2026-09-27, quick fix): back to your dot, qibla-up, and back to
    /// the qibla zoom if you'd zoomed well out — one camera move. Zoom is compared by how many
    /// metres the screen is across, which (unlike the region's span) doesn't grow when the map is
    /// turned.
    func homeQiblaUp(on user: CLLocationCoordinate2D) {
        guard let mapView, let camera = mapView.camera.copy() as? MKMapCamera else { return }
        camera.heading = Self.bearingToMecca(from: user)
        camera.centerCoordinate = user
        let midY = mapView.bounds.midY
        let left = mapView.convert(CGPoint(x: mapView.bounds.minX, y: midY), toCoordinateFrom: mapView)
        let right = mapView.convert(CGPoint(x: mapView.bounds.maxX, y: midY), toCoordinateFrom: mapView)
        let across = CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude))
        // How wide `qiblaSpan` shows the map in portrait (its longitude span is the tighter one).
        let target = MapView.Coordinator.qiblaSpan.longitudeDelta * 111_320 * cos(user.latitude * .pi / 180)
        if across > target * 1.5 {
            camera.centerCoordinateDistance *= target / across
        }
        mapView.setCamera(camera, animated: true)
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Default range: everything ever (the owner wants lifetime, not "this year").
        let now = Date()
        defaultStartDate = .distantPast
        defaultEndDate = now
        selectedStartDate = defaultStartDate
        selectedEndDate = defaultEndDate
        selectedPrayerNames = defaultPrayerNames

        Publishers.CombineLatest(Publishers.CombineLatest4($prayers, $selectedStartDate, $selectedEndDate, $selectedPrayerNames), $onlyAtMasjid)
            .map { inputs, masjid in
                let (prayers, start, end, names) = inputs
                return prayers.filter { $0.startTime >= start && $0.startTime <= end && names.contains($0.name) && (!masjid || $0.atMasjid) }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.filteredPrayers = $0 }
            .store(in: &cancellables)
    }

    /// Initial bearing of the great circle from `from` to the Kaaba, 0…360 clockwise from north.
    static func bearingToMecca(from: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180, lon1 = from.longitude * .pi / 180
        let lat2 = meccaCoordinate.latitude * .pi / 180, lon2 = meccaCoordinate.longitude * .pi / 180
        let y = sin(lon2 - lon1) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Shortest signed difference between two angles in degrees, -180…180.
    func angleDifference(from: Double, to: Double) -> Double { signedAngleDifference(from: from, to: to) }

    /// Pin colour for a completed prayer, same scale as the app's score colouring.
    static func markerColor(for prayer: PrayerModel) -> UIColor {
        UIColor(PrayerScoring.color(for: prayer.numberScore))
    }
}

/// Where the user's dot is on screen, updated continuously while the map moves so the qibla
/// ring can sit on the dot instead of the screen centre. @Observable: only the ring reads it.
@Observable final class MapAnchor {
    var userPoint: CGPoint? = nil
    /// Zoomed out past ~50 km across: the ring means nothing at that scale and hides.
    var zoomedOut = false
    /// Which way the map is turned (degrees clockwise from north at the top). The user can
    /// rotate it to line the map up with the street in front of them; everything the ring draws
    /// in screen space subtracts this.
    var mapHeading: Double = 0
}

/// Shortest signed way from `to` (where you point) round to `from` (the target), -180…180:
/// positive = turn right / clockwise.
func signedAngleDifference(from: Double, to: Double) -> Double {
    var diff = (from - to).truncatingRemainder(dividingBy: 360)
    if diff < -180 { diff += 360 }
    if diff > 180 { diff -= 360 }
    return diff
}

// MARK: - MapView

/// The MKMapView. The line to the Kaaba is computed from the user's position, not the compass
/// (phone compasses are often off), so lining the map up with the buildings around you tells you
/// the direction for a fact. The map was north-up until 2026-09-25; now the user can turn it with
/// two fingers so a street or wall on the map runs parallel to the phone's edge (owner: "instead of
/// rotating the whole phone"), and the ring on the dot turns with it (`MapAnchor.mapHeading`).
/// The compass only helps them turn.
struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: LocationViewModel
    var envLocation: EnvLocationManager
    var anchor: MapAnchor
    // Standard / Satellite (the globe button, MapModes.swift), remembered.
    @AppStorage(MapModes.satelliteKey) private var satellite = false
    /// The app's light / dark / auto setting (Settings), which the map follows (2026-09-27).
    var dark = false
    private var modesKey: String { "\(satellite)" }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.isRotateEnabled = true         // turn the map to match what's in front of you
        mapView.showsCompass = false           // our own glass north button (MapNorthButton)
        mapView.isPitchEnabled = false
        mapView.preferredConfiguration = MapModes.configuration(satellite: satellite)
        context.coordinator.appliedModes = modesKey
        mapView.overrideUserInterfaceStyle = dark ? .dark : .light
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        mapView.register(MeccaMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "MeccaAnnotationView")
        viewModel.mapView = mapView

        let mecca = MeccaAnnotation()
        mecca.coordinate = LocationViewModel.meccaCoordinate
        mecca.title = "Mecca"
        mapView.addAnnotation(mecca)

        // Start where the user is if we already have a fix; otherwise the first fix centres it.
        if let here = envLocation.userLocation?.coordinate {
            mapView.setRegion(MKCoordinateRegion(center: here, span: Coordinator.qiblaSpan), animated: false)
            context.coordinator.didCentreOnUser = true
            context.coordinator.userMoved(to: here, on: mapView)
            // Turn into qibla-up once it's on screen, so the user sees the map swing round.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak viewModel] in
                viewModel?.pointQiblaUp()
            }
        }
        context.coordinator.subscribe(to: viewModel, mapView: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        if mapView.overrideUserInterfaceStyle != style { mapView.overrideUserInterfaceStyle = style }
        // Only when the mode changed: a new configuration reloads the map's tiles.
        if context.coordinator.appliedModes != modesKey {
            context.coordinator.appliedModes = modesKey
            mapView.preferredConfiguration = MapModes.configuration(satellite: satellite)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let closeSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)   // ~900 m across: your block, not your borough
        /// Lining up to pray: ~220 m across, the buildings right around you (owner: 4× closer than
        /// closeSpan — "I double tap twice to get there").
        static let qiblaSpan = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        var parent: MapView
        var didCentreOnUser = false
        var appliedModes = ""
        private var prayerAnnotations: [CustomPrayerAnnotation] = []
        private var mosqueAnnotations: [MosqueAnnotation] = []
        private var qiblaLine: MKGeodesicPolyline?
        private var lineOrigin: CLLocation?
        private var cancellables = Set<AnyCancellable>()

        init(_ parent: MapView) { self.parent = parent }

        func subscribe(to viewModel: LocationViewModel, mapView: MKMapView) {
            // Pins: rebuilt once per filter change, never per pan.
            Publishers.CombineLatest(viewModel.$filteredPrayers, viewModel.$showPrayers)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak mapView] prayers, show in
                    guard let self, let mapView else { return }
                    self.setPrayers(show ? prayers : [], on: mapView)
                }
                .store(in: &cancellables)
            // Mosques: replaced whenever a search lands, hidden outside mosque mode.
            Publishers.CombineLatest(viewModel.$mosques, viewModel.$showMosques)
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak mapView] items, show in
                    guard let self, let mapView else { return }
                    self.setMosques(show ? items : [], on: mapView)
                }
                .store(in: &cancellables)
        }

        private func setMosques(_ items: [MKMapItem], on mapView: MKMapView) {
            mapView.removeAnnotations(mosqueAnnotations)
            mosqueAnnotations = items.map(MosqueAnnotation.init(item:))
            mapView.addAnnotations(mosqueAnnotations)
            if parent.viewModel.fitMosquesWhenFound, !mosqueAnnotations.isEmpty {
                parent.viewModel.fitMosquesWhenFound = false
                // You and the nearest few, not every result 30 km out.
                var shown: [MKAnnotation] = Array(mosqueAnnotations.prefix(6))
                if let me = mapView.userLocation.location { _ = me; shown.append(mapView.userLocation) }
                mapView.showAnnotations(shown, animated: true)
            }
        }

        private func setPrayers(_ prayers: [PrayerModel], on mapView: MKMapView) {
            mapView.removeAnnotations(prayerAnnotations)
            prayerAnnotations = prayers.compactMap { prayer in
                guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return nil }
                let a = CustomPrayerAnnotation()
                a.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                a.title = prayer.name
                a.subtitle = prayer.timeAtComplete?.formatted(date: .abbreviated, time: .shortened)
                a.prayer = prayer
                return a
            }
            mapView.addAnnotations(prayerAnnotations)
            updateVisibleCount(on: mapView)
        }

        /// Count the prayer pins in view (cluster members included) — MapKit's own bookkeeping.
        private func updateVisibleCount(on mapView: MKMapView) {
            // Our own pins in the visible rect. `annotations(in:)` returns clusters *and* their
            // members, which double-counted everything that was clustered.
            let rect = mapView.visibleMapRect
            let inView = prayerAnnotations.filter { rect.contains(MKMapPoint($0.coordinate)) }
            let count = inView.count
            if parent.viewModel.visiblePrayerCount != count { parent.viewModel.visiblePrayerCount = count }
            // The home list's rows: only when the set changed.
            let prayers = inView.compactMap(\.prayer)
            let old = parent.viewModel.visiblePrayers
            if prayers.count != old.count || Set(prayers.map(ObjectIdentifier.init)) != Set(old.map(ObjectIdentifier.init)) {
                parent.viewModel.visiblePrayers = prayers
            }
        }

        /// The tapped pin stays selected (bigger, green) while its sheet is up.
        func deselectAll(on mapView: MKMapView) {
            for a in mapView.selectedAnnotations { mapView.deselectAnnotation(a, animated: true) }
        }

        /// The user moved: redraw the great-circle line to the Kaaba and update the bearing.
        func userMoved(to coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            // Redraw once the dot has moved ~2 m: at the close qibla zoom a 25 m guard left the line
            // visibly starting off the dot (owner, 2026-09-26). New line first, then drop the old,
            // so it never blinks.
            if let origin = lineOrigin, origin.distance(from: here) < 2 { return }
            lineOrigin = here
            let line = MKGeodesicPolyline(coordinates: [coordinate, LocationViewModel.meccaCoordinate], count: 2)
            mapView.addOverlay(line, level: .aboveRoads)
            if let old = qiblaLine { mapView.removeOverlay(old) }
            qiblaLine = line
            let bearing = LocationViewModel.bearingToMecca(from: coordinate)
            if abs(parent.viewModel.qiblaBearing - bearing) > 0.5 { parent.viewModel.qiblaBearing = bearing }
        }

        /// The ring sits on the user's dot: report where the dot is on screen. Called on every
        /// frame of a pan/zoom (`mapViewDidChangeVisibleRegion`) and on every fix.
        private func updateAnchor(on mapView: MKMapView) {
            let heading = mapView.camera.heading
            if abs(parent.anchor.mapHeading - heading) > 0.05 { parent.anchor.mapHeading = heading }
            guard let coordinate = mapView.userLocation.location?.coordinate else {
                parent.anchor.userPoint = nil
                return
            }
            let point = mapView.convert(coordinate, toPointTo: mapView)
            if parent.anchor.userPoint != point { parent.anchor.userPoint = point }
            let zoomedOut = mapView.region.span.latitudeDelta > 0.5
            if parent.anchor.zoomedOut != zoomedOut { parent.anchor.zoomedOut = zoomedOut }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let coordinate = userLocation.location?.coordinate else { return }
            if !didCentreOnUser {
                didCentreOnUser = true
                mapView.setRegion(MKCoordinateRegion(center: coordinate, span: Self.qiblaSpan), animated: false)
                if !parent.viewModel.showPrayers && !parent.viewModel.showMosques {
                    parent.viewModel.pointQiblaUp(centre: coordinate)
                }
            }
            userMoved(to: coordinate, on: mapView)
            updateAnchor(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateAnchor(on: mapView)
            // Picking a prayer's spot: the pin in the middle follows the map (overlay only).
            if parent.viewModel.movingPrayer != nil {
                let pick = parent.viewModel.pick
                pick.centre = parent.viewModel.pickedCoordinate(on: mapView)
                if !pick.moving { pick.moving = true; parent.viewModel.liftPickPin(true) }
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if parent.viewModel.movingPrayer != nil {
                parent.viewModel.pick.centre = parent.viewModel.pickedCoordinate(on: mapView)
                parent.viewModel.pick.moving = false
                parent.viewModel.liftPickPin(false)
            }
            parent.viewModel.checkFocusDrift()
            updateVisibleCount(on: mapView)
            // Mosque mode: panned or zoomed out well past the last search → "Search this area".
            if parent.viewModel.showMosques, !parent.viewModel.mosqueSearching,
               let last = parent.viewModel.lastMosqueSearch {
                let a = CLLocation(latitude: last.center.latitude, longitude: last.center.longitude)
                let b = CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
                let lastRadius = last.span.latitudeDelta * 111_000 / 2
                let stale = a.distance(from: b) > lastRadius * 0.6 || mapView.region.span.latitudeDelta > last.span.latitudeDelta * 1.8
                if parent.viewModel.mosqueAreaStale != stale { parent.viewModel.mosqueAreaStale = stale }
            }
            updateAnchor(on: mapView)
            // Without a fix the ring sits at the screen centre and its arrow follows the map centre.
            if lineOrigin == nil {
                let bearing = LocationViewModel.bearingToMecca(from: mapView.centerCoordinate)
                if abs(parent.viewModel.qiblaBearing - bearing) > 0.5 { parent.viewModel.qiblaBearing = bearing }
            }
            // "At Mecca" when the Kaaba sits inside the ring (100 pt around the user / centre).
            let origin = mapView.userLocation.location?.coordinate ?? mapView.centerCoordinate
            let ringEdge = mapView.convert(CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY - 100), toCoordinateFrom: mapView)
            let centre = mapView.centerCoordinate
            let ringMetres = CLLocation(latitude: centre.latitude, longitude: centre.longitude)
                .distance(from: CLLocation(latitude: ringEdge.latitude, longitude: ringEdge.longitude))
            let toMecca = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                .distance(from: CLLocation(latitude: LocationViewModel.meccaCoordinate.latitude, longitude: LocationViewModel.meccaCoordinate.longitude))
            let atMecca = toMecca < ringMetres
            if parent.viewModel.isAtMecca != atMecca { parent.viewModel.isAtMecca = atMecca }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor.systemGreen.withAlphaComponent(0.9)
            renderer.lineWidth = 3
            renderer.lineCap = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is MeccaAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: "MeccaAnnotationView", for: annotation)
            }
            if let focus = annotation as? FocusPrayerAnnotation {
                // Like a selected pin: its score colour, bigger, a green glow, above everything.
                let view = MKMarkerAnnotationView(annotation: focus, reuseIdentifier: "focusPrayer")
                view.markerTintColor = LocationViewModel.markerColor(for: focus.prayer)
                view.glyphImage = UIImage(systemName: focus.prayer.atMasjid ? "building.columns.fill" : "hands.and.sparkles.fill")
                view.clusteringIdentifier = nil
                view.displayPriority = .required
                view.zPriority = .max
                view.canShowCallout = false
                view.isEnabled = false
                view.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
                view.layer.shadowColor = UIColor.systemGreen.cgColor
                view.layer.shadowOpacity = 0.9
                view.layer.shadowRadius = 10
                view.layer.shadowOffset = .zero
                return view
            }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation) as! MKMarkerAnnotationView
                let mosques = cluster.memberAnnotations.allSatisfy { $0 is MosqueAnnotation }
                let muted = cluster.memberAnnotations.allSatisfy { ($0 as? MosqueAnnotation).map { MosqueHiding.isHidden($0.item) } ?? false }
                view.markerTintColor = muted ? UIColor.systemGray3 : (mosques ? Self.mosqueTint : .systemGreen)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.canShowCallout = false
                view.displayPriority = .required
                return view
            }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation) as! MKMarkerAnnotationView
            if let mosque = annotation as? MosqueAnnotation {
                // Not recommended by the user: grey, and they give way to the rest.
                let muted = MosqueHiding.isHidden(mosque.item)
                let mine = MosqueFavorites.isFavorite(mosque.item)
                view.markerTintColor = muted ? UIColor.systemGray3 : Self.mosqueTint
                view.glyphText = nil
                view.glyphImage = UIImage(systemName: mine ? "star.fill" : MosqueIconStyle.current.pin)
                // Yours never hide inside a cluster.
                view.clusteringIdentifier = mine ? nil : (muted ? "mosqueMuted" : "mosque")
                view.canShowCallout = false
                view.displayPriority = muted ? .defaultLow : .required
                return view
            }
            view.glyphText = nil
            if let prayer = (annotation as? CustomPrayerAnnotation)?.prayer {
                view.markerTintColor = LocationViewModel.markerColor(for: prayer)
            }
            // Prayed at a masjid: the mosque mark instead of the hands.
            let atMasjid = (annotation as? CustomPrayerAnnotation)?.prayer?.atMasjid ?? false
            view.glyphImage = UIImage(systemName: atMasjid ? "building.columns.fill" : "hands.and.sparkles.fill") ?? UIImage(systemName: "mappin")
            view.clusteringIdentifier = "prayer"
            view.canShowCallout = false
            return view
        }

        /// Mosque pins: the app's green.
        static let mosqueTint = UIColor.systemGreen

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            // Picking a spot: pins are just scenery.
            if parent.viewModel.movingPrayer != nil || annotation is FocusPrayerAnnotation {
                mapView.deselectAnnotation(annotation, animated: false)
                return
            }
            // Mosques: a cluster zooms in to its mosques; one mosque opens its sheet.
            if let cluster = annotation as? MKClusterAnnotation, cluster.memberAnnotations.allSatisfy({ $0 is MosqueAnnotation }) {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }
            if let mosque = annotation as? MosqueAnnotation {
                UIView.animate(withDuration: 0.2) { view.transform = CGAffineTransform(scaleX: 1.3, y: 1.3) }
                view.zPriority = .max
                parent.viewModel.presentMosque(mosque.item)
                keepInView(annotation.coordinate, on: mapView)
                return
            }
            let prayers: [PrayerModel]
            if let cluster = annotation as? MKClusterAnnotation {
                prayers = cluster.memberAnnotations.compactMap { ($0 as? CustomPrayerAnnotation)?.prayer }
            } else if let prayer = (annotation as? CustomPrayerAnnotation)?.prayer {
                prayers = [prayer]
            } else { return }
            // Highlight: bigger, a green glow, on top of its neighbours. The pin keeps its score
            // colour (turning it green read as "Optimal").
            UIView.animate(withDuration: 0.2) {
                view.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            }
            view.layer.shadowColor = UIColor.systemGreen.cgColor
            view.layer.shadowOpacity = 0.9
            view.layer.shadowRadius = 10
            view.layer.shadowOffset = .zero
            view.zPriority = .max
            let selection = PrayerSpotSelection(prayers: prayers, coordinate: annotation.coordinate)
            parent.viewModel.present(selection)
            keepInView(annotation.coordinate, on: mapView)
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            UIView.animate(withDuration: 0.2) { view.transform = .identity }
            view.layer.shadowOpacity = 0
            view.zPriority = .defaultUnselected
        }

        /// Pan so the tapped pin isn't under the sheet (or the top controls) when it opens.
        private func keepInView(_ coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
            let bounds = mapView.bounds
            let point = mapView.convert(coordinate, toPointTo: mapView)
            let top: CGFloat = 130                                                  // below the pills
            let bottom = bounds.height - parent.viewModel.shownSheetHeight - 40     // above the sheet
            // Always centre the tapped pin in the part of the map the sheet leaves visible (it
            // used to move only when the pin was near an edge or under the sheet — owner wanted
            // every tap to land it in the middle).
            let target = CGPoint(x: bounds.midX, y: (top + bottom) / 2)
            guard hypot(point.x - target.x, point.y - target.y) > 2 else { return }
            let centre = CGPoint(x: bounds.midX + (point.x - target.x), y: bounds.midY + (point.y - target.y))
            mapView.setCenter(mapView.convert(centre, toCoordinateFrom: mapView), animated: true)
        }
    }
}

// MARK: - ContentView

struct LocationMapContentView: View {
    /// The qibla buzz's last beat (see the aligned task): kept across restarts of that task.
    @State private var lastAlignBuzz = Date.distantPast
    @StateObject private var viewModel = LocationViewModel()
    @AppStorage(MapModes.satelliteKey) private var satellite = false
    /// Light / dark / auto from Settings (0 light, 1 dark, 2 by the sun), like the rest of the app.
    @AppStorage("modeToggleNew") private var colorMode = 0
    private var appDark: Bool {
        colorMode == 1 || (colorMode == 2 && !prayerViewModel.isDaytime)
    }
    @EnvironmentObject private var prayerViewModel: PrayerViewModel
    @Environment(\.modelContext) private var context
    @EnvironmentObject var compass: CompassState
    @EnvironmentObject var envLocation: EnvLocationManager
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.dismiss) private var dismiss

    /// Every prayer with a recorded spot.
    @Query(filter: #Predicate<PrayerModel> { $0.latPrayedAt != nil && $0.longPrayedAt != nil },
           sort: \PrayerModel.startTime) private var prayers: [PrayerModel]
    @State private var showFilterSheet = false
    @State private var anchor = MapAnchor()
    /// First visit: how the qibla map works (owner, 2026-09-25: people don't get why the arrows
    /// don't follow the phone like the Salah page's compass). The ? in the controls reopens it.
    /// The explore dock is spread open (Qibla · Prayers · Mosques).
    @State private var exploreOpen = false

    /// The ? explains whatever layer is showing; each layer's guide also opens once by itself.
    @State private var guide: MapGuideTopic? = nil
    private var currentGuideTopic: MapGuideTopic {
        viewModel.showPrayers ? .prayers : viewModel.showMosques ? .mosques : .qibla
    }
    /// First visit to a layer: its guide, once (after the map / Explore sheet settle).
    private func showGuideIfFirstTime(_ topic: MapGuideTopic, after delay: Double) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: topic.seenKey) else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-demo") })
            && !ProcessInfo.processInfo.arguments.contains("-demoQiblaGuide") { return }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Another sheet up (usually Explore, right after picking the layer): try again when
            // it closes; only mark it seen once it has actually shown.
            guard currentGuideTopic == topic, guide == nil, !viewModel.showExplore, viewModel.selection == nil,
                  !showFilterSheet,
                  !defaults.bool(forKey: topic.seenKey) else { return }
            defaults.set(true, forKey: topic.seenKey)
            guide = topic
        }
    }
    @AppStorage(MosqueIconStyle.key) private var mosqueIconRaw = MosqueIconStyle.finder.rawValue
    private var mosqueIcon: MosqueIconStyle { MosqueIconStyle(rawValue: mosqueIconRaw) ?? .finder }

    /// Qibla (both off), prayers or mosques — one at a time.
    private func setMode(prayers: Bool, mosques: Bool) {
        let wasQibla = !viewModel.showPrayers && !viewModel.showMosques
        withAnimation {
            viewModel.showPrayers = prayers
            viewModel.showMosques = mosques
        }
        // Turning the map is for lining up to pray; browsing pins / mosques is north-up and
        // locked (owner, 2026-09-25).
        let qibla = !prayers && !mosques
        if qibla {
            viewModel.mapView?.isRotateEnabled = true
        } else {
            // Turn north first, lock after: with rotation disabled MapKit ignores the heading
            // change and the pins came up still qibla-rotated.
            viewModel.resetMapHeading()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak viewModel] in
                guard let viewModel, viewModel.showPrayers || viewModel.showMosques else { return }
                viewModel.mapView?.isRotateEnabled = false
                if abs(viewModel.mapView?.camera.heading ?? 0) > 0.5 { viewModel.resetMapHeading() }
            }
        }
        // The one sheet: up for either layer ("finding mosques…" until results land), opening at
        // half height from the qibla; switching layers keeps the user's height.
        if !mosques { viewModel.mosquePath = [] }
        if !prayers { viewModel.selection = nil; viewModel.setSpotMode(.browse) }
        if (prayers || mosques) && wasQibla { viewModel.sheetDetent = .medium }
        if mosques, viewModel.mosques.isEmpty, !viewModel.mosqueSearching {
            // First look: about 30 km around you.
            if let here = viewModel.mapView?.userLocation.location?.coordinate ?? envLocation.userLocation?.coordinate {
                viewModel.searchMosques(in: MKCoordinateRegion(center: here, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)), fit: true)
            }
        }
        if !prayers && !mosques {
            // Back from browsing: centred on you and qibla-up again, in one camera move.
            if let mapView = viewModel.mapView,
               let here = mapView.userLocation.location?.coordinate ?? envLocation.userLocation?.coordinate {
                if mapView.region.span.latitudeDelta > 0.004 {
                    mapView.setRegion(MKCoordinateRegion(center: mapView.centerCoordinate, span: MapView.Coordinator.qiblaSpan), animated: false)
                }
                viewModel.pointQiblaUp(centre: here)
            }
        }
    }

    private var inQiblaMode: Bool { !viewModel.showPrayers && !viewModel.showMosques }

    /// The last mosque search was around you (vs "Search this area" somewhere else).
    private var searchedNearYou: Bool {
        guard let centre = viewModel.lastMosqueSearch?.center,
              let here = viewModel.mapView?.userLocation.location ?? envLocation.userLocation else { return true }
        return here.distance(from: CLLocation(latitude: centre.latitude, longitude: centre.longitude)) < 3000
    }

    private var statusText: String {
        if viewModel.showPrayers {
            let n = viewModel.visiblePrayerCount
            return n == 1 ? "1 prayer in view" : "\(n) prayers in view"
        }
        if viewModel.showMosques {
            if viewModel.mosqueSearching { return "Finding mosques…" }
            let n = viewModel.mosques.filter { !MosqueHiding.isHidden($0) }.count
            let place = searchedNearYou ? "nearby" : "in this area"
            return n == 0 ? "No mosques found here" : n == 1 ? "1 mosque \(place)" : "\(n) mosques \(place)"
        }
        return compassHint
    }

    private func centreOnUser() {
        guard let mapView = viewModel.mapView,
              let here = mapView.userLocation.location?.coordinate ?? envLocation.userLocation?.coordinate else { return }
        let current = mapView.region.span
        let target = inQiblaMode ? MapView.Coordinator.qiblaSpan : MapView.Coordinator.closeSpan
        let zoomedOut = current.latitudeDelta > target.latitudeDelta * 1.5 || current.longitudeDelta > target.longitudeDelta * 1.5
        let span = zoomedOut ? target : current
        mapView.setRegion(MKCoordinateRegion(center: here, span: span), animated: true)
    }

    /// The compass pill: aligned, or which way and how far to turn.
    private var compassHint: String {
        if compass.qibla.aligned { return "Facing Mecca 🕋" }
        let diff = signedAngleDifference(from: viewModel.qiblaBearing, to: compass.heading)
        let degrees = Int(abs(diff).rounded())
        return diff < 0 ? "← Turn left \(degrees)°" : "Turn right \(degrees)° →"
    }

    /// A layer is on: its sheet is up.
    private var layerSheetUp: Bool { viewModel.showPrayers || viewModel.showMosques }
    private var sheetSmall: Bool { viewModel.sheetDetent == LocationViewModel.sheetSmall }

    /// What the one sheet shows: the layer's home (the list) or one pin's page, swapped in place.
    @ViewBuilder private var layerSheet: some View {
        ZStack(alignment: .top) {
            if viewModel.showMosques {
                if let item = viewModel.mosquePath.last {
                    MosqueSheet(item: item, back: { viewModel.openMosqueList() },
                                close: { setMode(prayers: false, mosques: false) })
                        .id(ObjectIdentifier(item))
                        .transition(.layerPage)
                } else {
                    MosqueListSheet(items: viewModel.mosques,
                                    origin: viewModel.mapView?.userLocation.location ?? envLocation.userLocation,
                                    nearYou: searchedNearYou,
                                    searching: viewModel.mosqueSearching,
                                    close: { setMode(prayers: false, mosques: false) },
                                    collapsed: sheetSmall) { viewModel.focusMosque($0) }
                        .transition(.layerPage)
                }
            } else if viewModel.showPrayers {
                if let selection = viewModel.selection {
                    PrayerSpotSheet(selection: selection, viewModel: viewModel,
                                    close: { setMode(prayers: false, mosques: false) })
                        .id(selection.id)
                        .transition(.layerPage)
                } else {
                    PrayerSpotsHome(viewModel: viewModel, collapsed: sheetSmall,
                                    custom: { showFilterSheet = true },
                                    close: { setMode(prayers: false, mosques: false) })
                        .transition(.layerPage)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The explore button: opens *in place* into the layers (owner, 2026-09-26: a sheet for three
    /// choices was friction). The lit layer tapped again goes back to the qibla.
    private var exploreDock: some View {
        let active: MapLayer = viewModel.showPrayers ? .prayers : viewModel.showMosques ? .mosques : .qibla
        return ExploreDock(open: $exploreOpen, active: active, mosqueIcon: mosqueIcon.pin) { layer in
            switch layer {
            case active: setMode(prayers: false, mosques: false)
            case .prayers: setMode(prayers: true, mosques: false)
            case .mosques: setMode(prayers: false, mosques: true)
            default: setMode(prayers: false, mosques: false)
            }
        }
    }

    var body: some View {
        ZStack {
            MapView(viewModel: viewModel, envLocation: envLocation, anchor: anchor, dark: appDark)
                .ignoresSafeArea()
                .onAppear { viewModel.prayers = prayers }
                .onChange(of: prayers.count) { _, _ in viewModel.prayers = prayers }

            // Qibla ring, sitting on the user's dot: the green line is the direction, the
            // ring's arrow repeats it and the chevron follows the compass.
            AnchoredQiblaRing(anchor: anchor, degrees: viewModel.qiblaBearing, isAtMecca: viewModel.isAtMecca)
                .opacity(inQiblaMode ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: inQiblaMode)

            // Facing Mecca: the whole screen edge glows green.
            AlignedEdgeGlow(on: compass.qibla.aligned && inQiblaMode)
                // The buzz on lining up, like the Salah circle's — qibla mode only (it went
                // missing when the circle's haptic was limited to the Salah page).
                // Buzzes the whole time you're lined up — once a second — and stops when you turn
                // off the line (owner, 2026-09-27, feedback 6FB814B9: not once per line-up).
                // Qibla mode only; the task ends when either changes.
                .task(id: compass.qibla.aligned && inQiblaMode && guide == nil) {
                    // Not under the map guide sheet. `lastAlignBuzz` outlives the task, so a
                    // heading wobbling across the threshold (restarting it) still buzzes at most
                    // about once a second.
                    guard compass.qibla.aligned && inQiblaMode && guide == nil else { return }
                    while !Task.isCancelled {
                        let wait = 1 - Date().timeIntervalSince(lastAlignBuzz)
                        if wait > 0 { try? await Task.sleep(for: .seconds(wait)); continue }
                        lastAlignBuzz = Date()
                        triggerSomeVibration(type: .heavy)
                        try? await Task.sleep(for: .seconds(1))
                    }
                }

            // Dock open: a tap anywhere on the map folds it back.
            if exploreOpen {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { exploreOpen = false } }
            }

            VStack {
                ZStack(alignment: .top) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            // A down chevron: the map slid up over the app, this sends it back.
                            Image(systemName: "chevron.down")
                                .mapControlIcon()
                        }
                        .buttonStyle(.plain)
                        .mapGlass(Circle())
                        .accessibilityLabel("Close map")
                        Spacer()
                    }

                    // Status pill: compass hint in qibla mode, count in prayers mode.
                    HStack {
                        Spacer()
                        // Prayer spots: the count, and the filter under it when one is on;
                        // tap → the filters (this replaced the bottom filter pill — Explore and
                        // this pill cover it).
                        VStack(spacing: 1) {
                            Text(statusText)
                                .font(.subheadline.weight(.medium))
                            if viewModel.showPrayers && viewModel.filtersActive {
                                Text(viewModel.filterSentence.replacingOccurrences(of: "Showing ", with: "").replacingOccurrences(of: "prayers from ", with: ""))
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.green)
                                    .lineLimit(1)
                            }
                        }
                        .monospacedDigit()
                        .fontDesign(.rounded)
                        .foregroundStyle(inQiblaMode && compass.qibla.aligned ? Color.green : Color.primary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 46)
                        .frame(maxWidth: 230)
                        .mapGlass(Capsule())
                        .contentShape(Capsule())
                        .onTapGesture { if viewModel.showMosques && !viewModel.mosques.isEmpty { viewModel.openMosqueList() } }
                            .overlay(Capsule().stroke(inQiblaMode && compass.qibla.aligned ? Color.green : Color.clear, lineWidth: 1.5))
                            .animation(.easeInOut(duration: 0.2), value: compass.qibla.aligned)
                        Spacer()
                    }
                    // Mosque mode, panned somewhere new: search there, right under the pill. It used
                    // to sit under the whole top row, whose right column (globe / locate / ?) is tall,
                    // so it landed mid-map over the pins (owner, 2026-09-27).
                    .overlay(alignment: .top) {
                        if viewModel.showMosques && viewModel.mosqueAreaStale, let mapView = viewModel.mapView {
                            Button {
                                viewModel.searchMosques(in: mapView.region, fit: false)
                            } label: {
                                Label("Search this area", systemImage: "magnifyingglass")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.green)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.white))
                                    .shadow(radius: 3)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 46 + 10)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            // Map style + locate: one glass capsule, like Apple Maps groups them.
                            VStack(spacing: 0) {
                                // Standard ⇄ Satellite.
                                Button { satellite.toggle() } label: {
                                    Image(systemName: MapModes.globeSymbol(longitude: envLocation.userLocation?.coordinate.longitude))
                                        .mapControlIcon()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(satellite ? "Standard map" : "Satellite map")
                                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 0.5)
                                Button { centreOnUser() } label: {
                                    Image(systemName: "location")
                                        .mapControlIcon()
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Centre on me")
                                // Only while the map is turned; its own view so rotating
                                // re-renders just it.
                                MapNorthButton(anchor: anchor, qiblaBearing: inQiblaMode ? viewModel.qiblaBearing : nil) {
                                    // Qibla: back to your dot as well; browsing pins / mosques: north only.
                                    if inQiblaMode {
                                        if let here = viewModel.mapView?.userLocation.location?.coordinate ?? envLocation.userLocation?.coordinate {
                                            viewModel.homeQiblaUp(on: here)
                                        } else {
                                            viewModel.pointQiblaUp()
                                        }
                                    } else { viewModel.resetMapHeading() }
                                }
                            }
                            .mapGlass(Capsule())
                            // Explore under the capsule (swapped with the ? — owner, map-one-sheet), so
                            // it stays reachable over a layer's sheet; it opens leftwards in place.
                            exploreDock
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)

                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.showPrayers)
            .animation(.easeInOut(duration: 0.2), value: viewModel.showMosques)
            .animation(.easeInOut(duration: 0.2), value: viewModel.mosqueAreaStale)
            // Moving a prayer's pin: the map's own controls step aside for the picker.
            .opacity(viewModel.movingPrayer == nil ? 1 : 0)
            .allowsHitTesting(viewModel.movingPrayer == nil)

            // "How this works", bottom right (swapped with Explore — owner, map-one-sheet); with a
            // layer's sheet up it floats just above it, like Apple Maps' controls.
            AboveSheet(metrics: viewModel.sheet, sheetUp: layerSheetUp) {
                HStack {
                    Spacer()
                    Button { guide = currentGuideTopic } label: {
                        Image(systemName: "questionmark")
                            .mapControlIcon()
                    }
                    .buttonStyle(.plain)
                    .mapGlass(Circle())
                    .accessibilityLabel("How this works")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .opacity(viewModel.movingPrayer == nil ? 1 : 0)
            .allowsHitTesting(viewModel.movingPrayer == nil)

            if let moving = viewModel.movingPrayer {
                MapPickOverlay(prayer: moving, pick: viewModel.pick)
                    .transition(.opacity)
            }

            // Panned away from the open prayer's pin: a way back to it, just above the sheet.
            if viewModel.focusDrifted, viewModel.selection != nil, let name = viewModel.focusName {
                AboveSheet(metrics: viewModel.sheet, sheetUp: true) {
                    Button { viewModel.centreFocus() } label: {
                        Label("Back to \(name)", systemImage: "scope")
                            .font(.subheadline.weight(.medium))
                            .fontDesign(.rounded)
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .mapGlass(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.movingPrayer != nil)
        .animation(.easeInOut(duration: 0.2), value: viewModel.focusDrifted)
        .onChange(of: viewModel.selection?.id) { _, id in
            // Back to the home list: drop the pin highlight.
            if id == nil, let mapView = viewModel.mapView {
                for a in mapView.selectedAnnotations where !(a is MosqueAnnotation) { mapView.deselectAnnotation(a, animated: true) }
            }
        }
        .onChange(of: viewModel.mosquePath.isEmpty) { _, empty in
            // Back to the list: the mosque's pin lets go.
            if empty, let mapView = viewModel.mapView {
                for a in mapView.selectedAnnotations where a is MosqueAnnotation { mapView.deselectAnnotation(a, animated: true) }
            }
        }
        // The one sheet (owner, map-one-sheet): up for as long as a layer is, never swiped away
        // (small is its header), its pages swapping in place.
        .sheet(isPresented: Binding(get: { layerSheetUp }, set: { _ in })) {
            layerSheet
                .environment(\.mapSheetCollapsed, sheetSmall && viewModel.spotMode == .browse)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewModel.sheet.height = $0 }
                .debugMapFrame("sheet")
                .coordinateSpace(.named("mapSheet"))
                .onDisappear { viewModel.sheet.height = 0 }
                .presentationDetents(viewModel.spotDetents, selection: $viewModel.sheetDetent)
                .presentationDragIndicator(viewModel.spotMode == .browse ? .visible : .hidden)
                .presentationBackgroundInteraction(viewModel.spotBackground)
                .presentationContentInteraction(.scrolls)   // lists scroll; the grabber resizes
                .interactiveDismissDisabled()
                // The ? (and a first-time guide) over the sheet while it's up.
                .sheet(item: Binding(get: { layerSheetUp ? guide : nil }, set: { guide = $0 })) { topic in
                    MapGuide(topic: topic) { guide = nil }
                        .presentationDetents([.height(470)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showFilterSheet) {
                    // Custom… from the filters: just the two dates.
                    CustomRangeSheet(viewModel: viewModel, earliest: prayers.first?.startTime ?? Date())
                        .presentationDetents([.height(220)])
                        .presentationDragIndicator(.visible)
                }
        }
        .sheet(item: Binding(get: { layerSheetUp ? nil : guide }, set: { guide = $0 })) { topic in
            MapGuide(topic: topic) { guide = nil }
                .presentationDetents([.height(470)])
                .presentationDragIndicator(.visible)
        }
        .onAppear { showGuideIfFirstTime(.qibla, after: 0.7) }   // let the map settle on the dot first
        .onChange(of: currentGuideTopic) { _, topic in
            if topic != .qibla { showGuideIfFirstTime(topic, after: 0.9) }
        }
        .onChange(of: viewModel.showExplore) { _, open in
            if !open { showGuideIfFirstTime(currentGuideTopic, after: 0.6) }   // Explore closed over a new layer
        }
        .onReceive(NotificationCenter.default.publisher(for: MosqueHiding.changed)) { _ in
            viewModel.mosques = viewModel.mosques   // re-add the pins so hidden ones turn grey
        }
        .toolbar(.hidden, for: .navigationBar)
        .whatsNewReturnPill()   // What's new → "Open in shukr" to the map
        #if DEBUG
        .task {
            // Simulator only: some past prayers with spots around City Hall, to see the pins.
            if ProcessInfo.processInfo.arguments.contains("-demoPrayerPins"), prayers.isEmpty {
                let names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
                let spots: [(Double, Double)] = [(40.7128, -74.0060), (40.7135, -74.0046), (40.7118, -74.0072),
                                                 (40.7152, -74.0091), (40.7103, -74.0098), (40.7163, -74.0033)]
                for i in 0..<26 {
                    let start = Date().addingTimeInterval(-Double(i) * 86_400 / 2.2)
                    let spot = spots[i % spots.count]
                    let p = PrayerModel(name: names[i % 5], startTime: start, endTime: start.addingTimeInterval(5400),
                                        latitude: spot.0 + Double(i % 3) * 0.0002, longitude: spot.1 - Double(i % 4) * 0.0002)
                    p.isCompleted = true
                    p.timeAtComplete = start.addingTimeInterval(Double(i % 5) * 900)
                    p.numberScore = [1.0, 0.9, 0.72, 0.4, 0.95][i % 5]
                    context.insert(p)
                }
                try? context.save()
            }
            if ProcessInfo.processInfo.arguments.contains("-demoMosques") {
                try? await Task.sleep(for: .seconds(2))
                setMode(prayers: false, mosques: true)
            }
            // `-demoMapLayer prayers|mosques|qibla` (the map opens on it; screenshots of the one sheet).
            if let layer = UserDefaults.standard.string(forKey: "demoMapLayer") {
                try? await Task.sleep(for: .seconds(2))
                setMode(prayers: layer == "prayers", mosques: layer == "mosques")
                if UserDefaults.standard.bool(forKey: "demoExploreOpen") {   // the dock, open (screenshots)
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { exploreOpen = true }
                }
                if let d = UserDefaults.standard.string(forKey: "demoMapDetent") {
                    try? await Task.sleep(for: .seconds(1))
                    viewModel.sheetDetent = d == "small" ? LocationViewModel.sheetSmall : d == "large" ? .large : .medium
                    if UserDefaults.standard.bool(forKey: "logMapFrames") {
                        try? await Task.sleep(for: .seconds(4))
                        print("MAPFRAME safe bottom=\(viewModel.mapView?.safeAreaInsets.bottom ?? -1) screen=\(UIScreen.main.bounds.height)")
                        MapFrameLog.dump()
                    }
                }
                // `-demoMapTour YES`: a pin, another pin, back to the list, 3 s apart (a recording
                // of the one sheet — simulated taps can't reach map pins everywhere).
                if UserDefaults.standard.string(forKey: "demoMapEdit") != nil, layer == "prayers" {
                    try? await Task.sleep(for: .seconds(3))
                    if let first = viewModel.visiblePrayers.first(where: { $0.timeAtComplete != nil }) { viewModel.open(first) }
                }
                if UserDefaults.standard.bool(forKey: "demoMapTour") {
                    try? await Task.sleep(for: .seconds(4))
                    if layer == "mosques" {
                        let pins = (viewModel.mapView?.annotations ?? []).compactMap { $0 as? MosqueAnnotation }
                            .sorted { $0.coordinate.latitude > $1.coordinate.latitude }
                        for pin in pins.prefix(2) {
                            viewModel.mapView?.selectAnnotation(pin, animated: true)
                            try? await Task.sleep(for: .seconds(3))
                        }
                        viewModel.openMosqueList()
                    } else {
                        // A cluster first (its list), then two prayers' pages.
                        let few = Array(viewModel.visiblePrayers.prefix(3))
                        if few.count > 1, let lat = few[0].latPrayedAt, let lon = few[0].longPrayedAt {
                            viewModel.present(PrayerSpotSelection(prayers: few, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                            try? await Task.sleep(for: .seconds(3))
                        }
                        for prayer in viewModel.visiblePrayers.prefix(2) {
                            viewModel.open(prayer)
                            try? await Task.sleep(for: .seconds(3))
                        }
                        viewModel.closeSpot()
                    }
                }
            }
        }
        #endif
    }
}

/// What the map shows besides the qibla.
enum MapLayer { case qibla, prayers, mosques, halal }

/// The map's Explore sheet (2026-09-25 — owner: prayer pins, mosques and soon halal food need one
/// home, not a button each): layer tiles like the pause screen's chips — tap one to show it, tap
/// it again to go back to the qibla — and the active layer's own settings underneath.
/// The map's explore button. Closed: one glass circle wearing the active layer's icon (🔍 on the
/// qibla). Open: it springs out leftwards into a glass capsule with Qibla · Prayers · Mosques
/// (icon over a small label, the active one green) and a ✕; picking one folds it back into that
/// layer's icon. Items fan in one after another.
struct ExploreDock: View {
    @Binding var open: Bool
    let active: MapLayer
    let mosqueIcon: String
    let pick: (MapLayer) -> Void
    @Namespace private var glass

    private var closedIcon: String {
        switch active {
        case .prayers: "hands.and.sparkles.fill"
        case .mosques: mosqueIcon
        default: "magnifyingglass"
        }
    }

    private var items: [(MapLayer, String, String)] {
        // No Qibla: it's the map's home, not a layer (owner, map-one-sheet) — a layer's ✕, or
        // tapping the lit layer here again, goes back to it.
        [(.prayers, "hands.and.sparkles.fill", "Prayers"),
         (.mosques, mosqueIcon, "Mosques")]
    }

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)

    var body: some View {
        // Under the globe / locate capsule it opens downwards (owner, map-one-sheet): the button
        // stays put and the layers drop in below it.
        VStack(spacing: 0) {
            Button {
                triggerSomeVibration(type: .light)
                withAnimation(spring) { open.toggle() }
            } label: {
                Image(systemName: open ? "xmark" : closedIcon)
                    .contentTransition(.symbolEffect(.replace))
                    .mapControlIcon(tint: open || active == .qibla ? nil : .green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Close" : "Explore: prayer spots, mosques")
            if open {
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 26, height: 0.5)
                    .transition(.opacity)
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let on = active == item.0
                    Button {
                        triggerSomeVibration(type: .light)
                        withAnimation(spring) { open = false }
                        pick(item.0)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.1)
                                .font(.system(size: 17, weight: .medium))
                                .frame(height: 20)
                            Text(item.2)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(on ? Color.green : Color.primary)
                        .frame(width: 46, height: 54)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(on ? Color.green.opacity(0.14) : .clear).padding(.horizontal, 3).padding(.vertical, 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4, anchor: .top).combined(with: .opacity)
                            .animation(spring.delay(0.04 * Double(i + 1))),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
                }
            }
        }
        .padding(.bottom, open ? 4 : 0)
        // As wide as the capsule above it, so the column of controls stays straight.
        .frame(width: 46)
        .mapGlass(Capsule(), tint: !open && active != .qibla ? .green : nil)
        .animation(spring, value: open)
    }
}

struct MapExploreSheet: View {
    let active: MapLayer
    let select: (MapLayer) -> Void
    @AppStorage(MosqueIconStyle.key) private var mosqueIconRaw = MosqueIconStyle.finder.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Explore")
                .font(.system(size: 24, weight: .light, design: .rounded))
                .padding(.top, 26)
            // Halal food stays hidden until it exists (a "soon" tile read as unfinished).
            HStack(spacing: 10) {
                tile("Qibla", icon: "location.north.line", layer: .qibla)
                tile("My prayer spots", icon: "hands.and.sparkles.fill", layer: .prayers)
                tile("Mosques", icon: (MosqueIconStyle(rawValue: mosqueIconRaw) ?? .finder).pin, layer: .mosques)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .fontDesign(.rounded)
    }

    private func tile(_ title: String, icon: String, layer: MapLayer) -> some View {
        let on = active == layer
        return Button {
            triggerSomeVibration(type: .light)
            select(layer)
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .light))
                    .frame(height: 24)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(on ? Color.green : Color.primary.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(on ? Color.green.opacity(0.14) : Color.primary.opacity(0.06))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Custom range for prayer spots: From and To, applied as you pick (the pins follow behind the
/// sheet), Done to close. Opens on the current range, or the last 30 days when it was a preset.
struct CustomRangeSheet: View {
    @ObservedObject var viewModel: LocationViewModel
    let earliest: Date
    @Environment(\.dismiss) private var dismiss

    private var firstDay: Date { Calendar.current.startOfDay(for: min(earliest, Date())) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Custom range")
                    .font(.system(size: 22, weight: .light, design: .rounded))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.green)
            }
            .padding(.top, 22)
            VStack(spacing: 0) {
                DatePicker("From", selection: $viewModel.selectedStartDate,
                           in: firstDay...viewModel.selectedEndDate, displayedComponents: .date)
                    .padding(.vertical, 8)
                Divider()
                DatePicker("To", selection: $viewModel.selectedEndDate,
                           in: viewModel.selectedStartDate...Date(), displayedComponents: .date)
                    .padding(.vertical, 8)
            }
            .font(.system(size: 16, weight: .light, design: .rounded))
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.05)))
            .tint(.green)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .onAppear {
            // A preset (all time starts at year 1): start from something you'd pick.
            if viewModel.quickRange != .custom {
                viewModel.selectedStartDate = max(firstDay, Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? firstDay)
                viewModel.selectedEndDate = Date()
            }
        }
    }
}

/// A soft green glow hugging the screen edge while the user faces the Kaaba.
struct AlignedEdgeGlow: View {
    let on: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .strokeBorder(Color.green.opacity(0.9), lineWidth: 26)
                .blur(radius: 26)
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .strokeBorder(Color.green.opacity(0.8), lineWidth: 5)
                .blur(radius: 5)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .opacity(on ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: on)
    }
}

/// The qibla ring positioned on the user's dot (screen centre until there's a fix). Reads the
/// anchor per map frame; only this view re-renders for it.
struct AnchoredQiblaRing: View {
    var anchor: MapAnchor
    let degrees: Double
    let isAtMecca: Bool
    var body: some View {
        GeometryReader { geo in
            CircleWithArrowOverlay(degrees: degrees, isAtMecca: isAtMecca, ringHidden: anchor.zoomedOut,
                                   mapHeading: anchor.mapHeading)
                .position(anchor.userPoint ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The map's floating buttons: white pill, green glyph (filled: green pill, white glyph).
/// The map's controls, current-iOS style (owner, 2026-09-25: the white squares looked dated):
/// Liquid Glass on iOS 26+, frosted material before that. Icons in the primary colour, green only
/// for "on".
extension View {
    func mapControlIcon(tint: Color? = nil) -> some View {
        self
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint ?? Color.primary)
            .frame(width: 46, height: 46)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    func mapGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(tint.map { .regular.tint($0.opacity(0.18)).interactive() } ?? .regular.interactive(), in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        }
    }
}

struct MapPill: ButtonStyle {
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(filled ? Color.white : Color.green)
            .frame(minWidth: 18, minHeight: 18)
            .padding(14)
            .background(filled ? Color.green : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - CircleWithArrowOverlay
struct CircleWithArrowOverlay: View {
    @EnvironmentObject var compass: CompassState
    @EnvironmentObject var sharedState: SharedStateClass
    var degrees: Double
    var isAtMecca: Bool
    /// Zoomed out: the ring and its bearing triangle fade; the compass chevron stays on the dot.
    var ringHidden: Bool = false
    /// How far the map is turned; the ring draws in screen space, so bearings subtract it.
    var mapHeading: Double = 0
    
    var body: some View {
        ZStack {
            // Change the circle's color based on isAtMecca:
            Circle()
                .stroke(lineWidth: isAtMecca || compass.qibla.aligned ? 4 : 2)
                .frame(width: 200, height: 200)
                .foregroundColor(isAtMecca || compass.qibla.aligned ? .green : .white)
                .shadow(color: isAtMecca || compass.qibla.aligned ? .white.opacity(0.7) : .black.opacity(0.1), radius: 10, x: 0, y: 0)
                .animation(.default, value: compass.qibla.aligned)
                .opacity(ringHidden ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: ringHidden)

            // How far to turn: a green arc along the ring from where you point (chevron) to
            // the Kaaba (triangle). It shrinks as you turn and is gone when aligned.
            if !isAtMecca && !compass.qibla.aligned {
                let diff = signedAngleDifference(from: degrees, to: compass.heading)   // + = clockwise
                let start = diff >= 0 ? compass.heading : degrees                       // clockwise start
                Circle()
                    .trim(from: 0, to: abs(diff) / 360)
                    .stroke(Color.green.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(start - mapHeading - 90))   // trim starts at 3 o'clock; put it at `start`
                    .opacity(ringHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: ringHidden)
            }

            // Only show the arrows if we're not at Mecca
            if !isAtMecca {
                Image(systemName: "arrowtriangle.up.fill")
                    .resizable()
                    .foregroundColor(compass.qibla.aligned ? .green : .white)
                    .frame(width: 20, height: 20)
                    .offset(y: -110)
                    .rotationEffect(.degrees(degrees - mapHeading))
                    .animation(.default, value: compass.qibla.aligned)
                    .opacity(ringHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.25), value: ringHidden)

                // second (compass) arrow using your locationManager.
                // This uses the compassHeading from your environment object.
                Image(systemName: "chevron.up")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(compass.qibla.aligned ? .green : Color(.systemBlue))
                    .background(
                        Circle() // to increase tappable area
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 44, height: 44)
                    )
                    .shadow(radius: 2)
//                    .opacity(0.7)
                    .offset(y: -20)
                    .rotationEffect(Angle(degrees: (compass.qibla.aligned ? degrees : compass.heading) - mapHeading))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: degrees)
            }
        }
        .frame(width: 200, height: 200)

/*
        ZStack {
            Circle()
                .stroke(lineWidth: 2)
                .frame(width: 200, height: 200)
                .foregroundColor(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)

            Image(systemName: "arrowtriangle.up.fill")
                .resizable()
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .offset(y: -100)
                .rotationEffect(.degrees(degrees))
                .animation(.easeInOut, value: degrees)
            
            // Compass Based Qibla Arrow
            Image(systemName: "chevron.up")
                .font(.subheadline)
                .foregroundColor(compass.qibla.aligned ? .green : .primary)
                .background(
                    Circle() // this is to increase tappable aread
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 44, height: 44)
                )
                .opacity(0.7)
                .offset(y: -80)
//                            .rotationEffect(Angle(degrees: compass.qibla.aligned ? 0 : compass.qibla.heading))
                .rotationEffect(Angle(degrees: compass.heading))
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: compass.qibla.aligned)
//                            .onChange(of: compass.qibla.aligned) { _, newIsAligned in
//                                checkToTriggerQiblaHaptic(aligned: newIsAligned)
//                            }
//                            .onTapGesture { showQiblaMap = true }
        }
        .frame(width: 200, height: 200)
 */
    }
}

// The rest of your code remains the same (CheckboxStyle, FilterView, PrayerDetailView, ClusterPrayersDetailView)




// MARK: - Custom Checkbox ToggleStyle

// MARK: - FilterView
struct FilterView: View {
    @Binding var selectedStartDate: Date
    @Binding var selectedEndDate: Date
    @Binding var selectedPrayerNames: Set<String>

    let defaultStartDate: Date
    let defaultEndDate: Date
    let defaultPrayerNames: Set<String>
    /// What the start picker shows while the range is "all time" (`.distantPast` would read 0001).
    var earliestPinDate: Date = Date()

    @Environment(\.dismiss) var dismiss

    private var currentRange: LocationViewModel.QuickRange {
        let cal = Calendar.current
        for r in LocationViewModel.QuickRange.allCases {
            guard let d = r.dates() else { continue }
            let sameStart = r == .allTime ? selectedStartDate == .distantPast : cal.isDate(selectedStartDate, inSameDayAs: d.start)
            if sameStart && cal.isDate(selectedEndDate, inSameDayAs: d.end) { return r }
        }
        return .custom
    }
    private func apply(_ range: LocationViewModel.QuickRange) {
        guard let d = range.dates() else { return }
        selectedStartDate = d.start
        selectedEndDate = d.end
    }
    private var isDefault: Bool {
        selectedStartDate == defaultStartDate && Calendar.current.isDate(selectedEndDate, inSameDayAs: defaultEndDate) && selectedPrayerNames == defaultPrayerNames
    }

    let allPrayerNames = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // WHEN: a grid of range chips
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("When")
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(LocationViewModel.QuickRange.allCases) { range in
                                let on = currentRange == range
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        if range == .custom {
                                            if currentRange != .custom { selectedStartDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date() }
                                        } else { apply(range) }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: range.symbol).font(.subheadline)
                                        Text(range.rawValue).lineLimit(1).minimumScaleFactor(0.85)
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(on ? Color.green : Color.primary)
                                    .background(on ? Color.green.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.green.opacity(on ? 0.35 : 0), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if currentRange == .custom {
                            VStack(spacing: 0) {
                                dateRow("From", selection: Binding(
                                    get: { selectedStartDate == .distantPast ? earliestPinDate : selectedStartDate },
                                    set: { selectedStartDate = $0 }
                                ), in: ...selectedEndDate)
                                Divider().padding(.leading, 16)
                                dateRow("To", selection: $selectedEndDate, in: selectedStartDate...Date())
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }

                    // PRAYERS: five icon chips
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionTitle("Prayers")
                            Spacer()
                            Button(selectedPrayerNames == defaultPrayerNames ? "All on" : "Select all") {
                                withAnimation(.snappy(duration: 0.2)) { selectedPrayerNames = defaultPrayerNames }
                            }
                            .font(.caption.weight(.medium))
                            .disabled(selectedPrayerNames == defaultPrayerNames)
                        }
                        HStack(spacing: 8) {
                            ForEach(allPrayerNames, id: \.self) { name in
                                let on = selectedPrayerNames.contains(name)
                                Button {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        if on { selectedPrayerNames.remove(name) } else { selectedPrayerNames.insert(name) }
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: prayerSymbol(name)).font(.title3)
                                        Text(name).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(on ? Color.green : Color.secondary)
                                    .background(on ? Color.green.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.green.opacity(on ? 0.35 : 0), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .fontDesign(.rounded)
            .navigationTitle("Filter Prayers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withAnimation(.snappy(duration: 0.2)) {
                            selectedStartDate = defaultStartDate
                            selectedEndDate = defaultEndDate
                            selectedPrayerNames = defaultPrayerNames
                        }
                    }
                    .disabled(isDefault)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
    }
    private func dateRow(_ label: String, selection: Binding<Date>, in range: ClosedRange<Date>) -> some View {
        HStack {
            Text(label)
            Spacer()
            DatePicker("", selection: selection, in: range, displayedComponents: [.date]).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
    private func dateRow(_ label: String, selection: Binding<Date>, in range: PartialRangeThrough<Date>) -> some View {
        HStack {
            Text(label)
            Spacer()
            DatePicker("", selection: selection, in: range, displayedComponents: [.date]).labelsHidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

/// The SF Symbol the app uses for each prayer (same set as the circle and the spot sheet).
func prayerSymbol(_ name: String) -> String {
    switch name {
    case "Fajr": return "sunrise.fill"
    case "Dhuhr": return "sun.max.fill"
    case "Asr": return "sun.haze.fill"
    case "Maghrib": return "sunset.fill"
    case "Isha": return "moon.stars.fill"
    default: return "circle"
    }
}

// MARK: - PrayerDetailView
/// What was tapped on the map: the prayers at one pin or in one cluster.
/// The prayer map as a spot picker, above the prayer's sheet: the question on top and a pin fixed
/// in the middle of the visible map (the card is in the sheet).
struct MapPickOverlay: View {
    let prayer: PrayerModel
    let pick: SpotPickState

    var body: some View {
        // The pin itself is drawn inside the map view (`PickPinView`), where the spot is read.
        VStack {
            SpotPickerTitle(prayerName: prayer.displayName)
                .padding(.top, 8)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

/// The picking pin, a subview of the map, so its tip is exactly the point the spot is read from:
/// the shared `PickPin` (Apple's `mappin` — D5818BB9), hosted here. Lifts while the map moves.
final class PickPinView: UIView {
    private final class State: ObservableObject { @Published var lifted = false }
    private struct Host: View {
        @ObservedObject var state: State
        var body: some View { PickPin(lifted: state.lifted) }
    }
    private let state = State()
    private let host: UIHostingController<Host>

    init(tip: CGPoint) {
        host = UIHostingController(rootView: Host(state: state))
        let size = PickPin.size, t = PickPin.tip
        super.init(frame: CGRect(x: tip.x - t.x, y: tip.y - t.y, width: size.width, height: size.height))
        isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        host.view.frame = bounds
        host.view.isUserInteractionEnabled = false
        addSubview(host.view)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setLifted(_ lifted: Bool) { state.lifted = lifted }
}

extension AnyTransition {
    /// Content swapping inside a sheet that is resizing to fit it: what leaves goes quickly, what
    /// arrives fades in a beat later, so the two never sit on top of each other.
    static func sheetContent(offset: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: offset)).animation(.easeOut(duration: 0.28).delay(0.12)),
            removal: .opacity.animation(.easeIn(duration: 0.1)))
    }
}

struct PrayerSpotSelection: Identifiable {
    let id = UUID()
    let prayers: [PrayerModel]
    let coordinate: CLLocationCoordinate2D
    /// Open a cluster's sheet straight on this prayer's page (the list behind it).
    var focus: PrayerModel? = nil
}

// MARK: - PrayerSpotSheet

/// The half sheet for a tapped pin or cluster: a headline, per-prayer counts and the average
/// score for a cluster, then every prayer newest first grouped by day with when it was prayed,
/// where that fell in its window, and its score.
struct PrayerSpotSheet: View {
    let selection: PrayerSpotSelection
    let viewModel: LocationViewModel
    /// ✕: leave prayer spots, back to the qibla.
    let close: () -> Void
    @State private var address: String? = nil
    /// A cluster's list swaps to a prayer's page in place (the one sheet — no push, no second
    /// sheet); ‹ on the page comes back to the list.
    @State private var opened: PrayerModel?
    private var prayers: [PrayerModel] { selection.prayers }

    init(selection: PrayerSpotSelection, viewModel: LocationViewModel, close: @escaping () -> Void) {
        self.selection = selection
        self.viewModel = viewModel
        self.close = close
        _opened = State(initialValue: selection.focus)
    }

    /// Street + city for the pin, reverse-geocoded once per spot (cached on the view model).
    private func loadAddress() async {
        let c = selection.coordinate
        let key = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        if let cached = viewModel.addressCache[key] { address = cached; return }
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let place = [street.isEmpty ? placemark?.name : street, placemark?.locality].compactMap { $0 }.joined(separator: ", ")
        guard !place.isEmpty else { return }
        viewModel.addressCache[key] = place
        address = place
    }

    private var sorted: [PrayerModel] {
        prayers.sorted { ($0.timeAtComplete ?? $0.startTime) > ($1.timeAtComplete ?? $1.startTime) }
    }
    private var days: [(date: Date, prayers: [PrayerModel])] {
        let cal = Calendar.current
        var order: [Date] = []; var byDay: [Date: [PrayerModel]] = [:]
        for p in sorted {
            let day = cal.startOfDay(for: p.timeAtComplete ?? p.startTime)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(p)
        }
        return order.map { (date: $0, prayers: byDay[$0] ?? []) }
    }
    private var averageScore: Double? {
        let scored = prayers.compactMap(\.numberScore)
        return scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
    }
    /// "Fajr 3 · Dhuhr 5 …" in prayer order.
    private var countsLine: String {
        ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"].compactMap { name in
            let n = prayers.filter { $0.name == name }.count
            return n > 0 ? "\(name) \(n)" : nil
        }.joined(separator: " · ")
    }

    var body: some View {
        ZStack(alignment: .top) {
            if prayers.count == 1, let only = prayers.first {
                // One pin: its page right away; ‹ goes back to the home list.
                PrayerSpotDetail(prayer: only, selection: selection, viewModel: viewModel,
                                 back: { viewModel.closeSpot() }, close: close)
            } else if let opened {
                PrayerSpotDetail(prayer: opened, selection: selection, viewModel: viewModel,
                                 back: { withAnimation(LocationViewModel.pageSwap) { self.opened = nil } }, close: close)
                    .transition(.layerPage)
            } else if collapsed {
                MapSheetCollapsed { clusterHeader }
            } else {
                clusterList
                    .transition(.layerPage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: selection.id) { await loadAddress() }
    }

    @Environment(\.mapSheetCollapsed) private var collapsed
    private var clusterHeader: some View {
        MapSheetHeader(back: { viewModel.closeSpot() }, title: "\(prayers.count) prayers here",
                       subtitle: address ?? "Locating…", close: close)
    }

    private var clusterList: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    clusterHeader
                        .padding(.bottom, 4)
                    Text(countsLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let avg = averageScore {
                        HStack(spacing: 6) {
                            ScoreDot(score: avg)
                            Text("Average score \(Int((avg * 100).rounded()))%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 4, trailing: 20))
            }

            ForEach(days, id: \.date) { day in
                Section(zikrDayLabel(day.date)) {
                    ForEach(day.prayers) { prayer in
                        Button {
                            withAnimation(LocationViewModel.pageSwap) { opened = prayer }
                        } label: {
                            HStack {
                                PrayerSpotRow(prayer: prayer)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .fontDesign(.rounded)
    }
}

/// One prayer's page in the spot sheet (redesigned 2026-09-26 — owner: the card rows looked
/// tappable and weren't, the blue ··· squeezed the header). Reading: the score, the prayer's window
/// as the time editor's coloured bar with a marker where it was prayed, where, and "edited ·
/// you marked it…" notes with a one-tap Undo. One Edit button at the bottom turns the same sheet
/// into the editor: the bar scrubs and the wheel appears, and the location row opens the picker —
/// the map above becomes it and the sheet holds the address / distance card
/// (`LocationViewModel.spotMode`). Save keeps both; Cancel drops both. Its own pin is lifted out of
/// any cluster while the page is open.
struct PrayerSpotDetail: View {
    let prayer: PrayerModel
    let selection: PrayerSpotSelection
    @ObservedObject var viewModel: LocationViewModel
    /// ‹: to the cluster's list, or the home list for a single pin.
    let back: () -> Void
    /// ✕: leave prayer spots.
    let close: () -> Void
    @EnvironmentObject private var prayerViewModel: PrayerViewModel
    @State private var address: String?
    /// Editing: the picked time and spot wait here until Save.
    @State private var draftTime = Date()
    @State private var draftSpot: CLLocationCoordinate2D?
    @State private var draftAddress: String?

    private var editing: Bool { viewModel.spotMode != .browse }
    private var picking: Bool { viewModel.spotMode == .pickSpot }

    private var spot: CLLocationCoordinate2D? {
        guard let lat = prayer.latPrayedAt, let lon = prayer.longPrayedAt else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    /// From the prayer's start to now or the next Fajr, like the Salah list's editor.
    private var editRange: ClosedRange<Date> {
        let latest = min(Date(), PrayerDay.rolloverInstant(after: prayer.startTime))
        return prayer.startTime...max(prayer.startTime, latest)
    }
    /// The score shown: live while editing the time.
    private var shownScore: Double? {
        guard editing else { return prayer.numberScore }
        guard editRange.contains(draftTime) else { return nil }
        return prayer.isJumuah ? 1 : PrayerScoring.score(start: prayer.startTime, end: prayer.endTime, markedAt: draftTime)
    }
    private var shownGrade: String {
        guard let s = shownScore else { return editing ? "not a valid time" : "Missed" }
        return prayer.isJumuah ? "Jumu'ah" : PrayerScoring.grade(for: s).rawValue
    }
    private var scoreColor: Color { PrayerScoring.color(for: shownScore) }
    private var timeChanged: Bool {
        guard let at = prayer.timeAtComplete else { return true }
        return abs(draftTime.timeIntervalSince(at)) >= 30
    }
    private var canSave: Bool { editRange.contains(draftTime) && (timeChanged || draftSpot != nil) }

    private func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        let m = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        return Measurement(value: m, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.significantDigits(1...2))))
    }

    @Environment(\.mapSheetCollapsed) private var collapsed

    var body: some View {
        ZStack {
            if collapsed && !editing {
                MapSheetCollapsed { header }
            } else {
                column
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fontDesign(.rounded)
        // The page keeps the user's height (the one sheet); its pin is lifted out and centred above it.
        .onAppear {
            viewModel.focus(on: prayer, sheetFraction: viewModel.pageFraction)
        }
        // Back from picking: the prayer's own pin returns, centred again.
        .onChange(of: viewModel.spotMode) { old, mode in
            if old == .pickSpot, mode != .pickSpot { viewModel.focus(on: prayer, sheetFraction: viewModel.pageFraction) }
        }
        .onDisappear {
            viewModel.clearFocus(prayer)
            if editing { viewModel.setSpotMode(.browse) }
        }
        .task(id: spot.map { "\($0.latitude),\($0.longitude)" }) {
            if let spot { address = await PrayerSpotAddress.lookUp(spot) }
        }
        .task(id: draftSpot.map { "\($0.latitude),\($0.longitude)" }) {
            draftAddress = nil
            if let draftSpot { draftAddress = await PrayerSpotAddress.lookUp(draftSpot) }
        }
        #if DEBUG
        .task { await demoEdit() }
        #endif
    }

    /// One column at its natural height; while editing the sheet is exactly that tall
    /// (`setPageHeight`), so whatever unfolds in it — the wheel, the address card — grows the
    /// sheet with it in the same spring.
    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            if picking {
                // Picking a spot: the card; the map above is the picker.
                SpotPickerCard(original: draftSpot ?? spot, recorded: viewModel.pick.recorded,
                               centre: viewModel.pick.centre, moving: viewModel.pick.moving,
                               onJump: { viewModel.jumpPick(to: $0) },
                               onCancel: { viewModel.stopPicking() },
                               onSet: { picked in
                                   draftSpot = picked
                                   viewModel.stopPicking()
                               },
                               embedded: true, setTitle: "Done",
                               onSearching: { on in
                                   withAnimation(LocationViewModel.sheetSpring) {
                                       viewModel.sheetDetent = on ? .large : viewModel.pageDetent
                                   }
                               })
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 14)
                    .transition(.sheetContent(offset: 10))
            } else {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .transition(.opacity)
                if editing {
                    VStack(alignment: .leading, spacing: 18) {
                        PrayerTimeEditor(prayer: prayer, draft: $draftTime, range: editRange, showsScore: false)
                        locationButton
                        SaveCancelButtons(canSave: canSave, onCancel: {
                            draftSpot = nil
                            viewModel.setSpotMode(.browse)
                        }, onSave: save)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                    .transition(.sheetContent(offset: -10))
                } else {
                    reading
                        .transition(.sheetContent(offset: 0))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewModel.setPageHeight($0) }
    }

    #if DEBUG
    /// `-demoMapEdit YES` (with `-demoMapLayer prayers`): Edit → an earlier time → Change location →
    /// the map moves → Done → Save → Undo time → Undo spot, 2–3 s apart, logging the sheet's height
    /// ("MAPEDIT"). The same calls the buttons make; simulated taps can't reach this sheet everywhere.
    private static var demoEditRan = false
    private func demoEdit() async {
        guard UserDefaults.standard.string(forKey: "demoMapEdit") != nil, !Self.demoEditRan else { return }
        Self.demoEditRan = true
        func log(_ step: String) {
            print("MAPEDIT \(step): mode=\(viewModel.spotMode) detent=\(viewModel.sheetDetent) page=\(Int(viewModel.pageHeight)) sheet=\(Int(viewModel.sheet.height))")
        }
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        await wait(2.5); log("page")
        draftTime = prayer.timeAtComplete.map { min(max($0, editRange.lowerBound), editRange.upperBound) } ?? editRange.upperBound
        draftSpot = nil
        viewModel.setSpotMode(.editTime)
        await wait(2.5); log("edit")
        draftTime = max(editRange.lowerBound, draftTime.addingTimeInterval(-10 * 60))
        await wait(2); log("time -10 min")
        if let from = spot { viewModel.startPicking(prayer, at: from, recorded: prayer.recordedSpot ?? spot) }
        await wait(2.5); log("picking")
        if let from = spot { viewModel.jumpPick(to: CLLocationCoordinate2D(latitude: from.latitude + 0.0012, longitude: from.longitude)) }
        await wait(2.5)
        if let mapView = viewModel.mapView { draftSpot = viewModel.pickedCoordinate(on: mapView) }
        viewModel.stopPicking()
        await wait(2.5); log("picked → editor")
        save()
        await wait(3); log("saved (timeEdited=\(prayer.timeEdited) spotEdited=\(prayer.spotEdited))")
        prayerViewModel.revertPrayerTime(prayer)
        viewModel.refreshPins()
        await wait(2.5); log("undo time (timeEdited=\(prayer.timeEdited))")
        prayerViewModel.revertPrayerLocation(prayer)
        viewModel.refreshPins()
        viewModel.focus(on: prayer, sheetFraction: viewModel.pageFraction)
        await wait(2.5); log("undo spot (spotEdited=\(prayer.spotEdited))")
    }
    #endif

    /// The reading page under the header: when, where, and a quiet Edit (owner: the big button was
    /// far too loud).
    private var reading: some View {
        VStack(alignment: .leading, spacing: 16) {
            timeSection
            Divider()
            locationSection
            Button {
                draftTime = prayer.timeAtComplete.map { min(max($0, editRange.lowerBound), editRange.upperBound) } ?? editRange.upperBound
                draftSpot = nil
                viewModel.setSpotMode(.editTime)
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: header

    /// The shared header: ‹ (not while editing — Save / Cancel decide), the prayer's icon in its
    /// score colour, name and date, the score, ✕.
    private var header: some View {
        // No ✕ on a single prayer's page: ‹ is enough (owner, map-one-sheet).
        MapSheetHeader(back: editing ? nil : back,
                       title: prayer.displayName,
                       subtitle: prayer.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())) {
            Image(systemName: prayerSymbol(prayer.name))
                .font(.title3)
                .foregroundStyle(scoreColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(scoreColor.opacity(0.15)))
        } trailing: {
            VStack(alignment: .trailing, spacing: 0) {
                Text(shownScore.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(shownGrade)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(shownScore == nil ? .secondary : scoreColor)
            }
            .animation(.snappy, value: shownScore)
        }
    }

    // MARK: reading

    /// "29 min after the window ended at 4:10 PM" / "1h 14m into the window · 12:49 – 4:10 PM".
    private func whenLine(_ at: Date) -> String {
        let window = "\(shortTimePM(prayer.startTime)) – \(shortTimePM(prayer.endTime))"
        func span(_ secs: TimeInterval) -> String {
            let m = max(Int(secs / 60), 0)
            return m < 60 ? "\(m) min" : "\(m / 60)h \(m % 60)m"
        }
        if at > prayer.endTime {
            return "\(span(at.timeIntervalSince(prayer.endTime))) after the window ended at \(shortTimePM(prayer.endTime))"
        }
        if at < prayer.startTime { return "before the window opened · \(window)" }
        return "\(span(at.timeIntervalSince(prayer.startTime))) into the window · \(window)"
    }

    /// The prayer's window as the time editor's bar, the marker where it was prayed.
    @ViewBuilder private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let at = prayer.timeAtComplete {
                PrayerWindowBar(start: prayer.startTime, end: prayer.endTime, marked: at, color: scoreColor)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prayed \(shortTimePM(at))").font(.body.weight(.medium))
                    Text(whenLine(at)).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            if prayer.timeEdited, let recorded = prayer.recordedTimeAtComplete {
                editedNote("edited · you marked it at \(shortTimePM(recorded))") {
                    prayerViewModel.revertPrayerTime(prayer)
                    viewModel.refreshPins()
                }
            }
        }
    }

    @ViewBuilder private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: prayer.atMasjid ? "building.columns" : "mappin.and.ellipse")
                    .foregroundStyle(prayer.atMasjid ? Color.sage : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(prayer.atMasjid ? (prayer.mosqueName ?? "") : (address ?? "Locating…"))
                        .lineLimit(1)
                    if prayer.atMasjid, let address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            if prayer.spotEdited, let recorded = prayer.recordedSpot, let spot {
                editedNote("edited · you marked it \(distance(recorded, spot)) away") {
                    prayerViewModel.revertPrayerLocation(prayer)
                    viewModel.refreshPins()
                    viewModel.focus(on: prayer, sheetFraction: viewModel.pageFraction)
                }
            }
        }
    }

    /// "✎ edited · you marked it at 9:05 PM      Undo"
    private func editedNote(_ text: String, undo: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Label(text, systemImage: "pencil")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Undo", action: undo)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.green)
                .buttonStyle(.plain)
        }
    }

    // MARK: editing

    /// Where it was prayed, while editing: now a real button (→ the picker).
    private var locationButton: some View {
        let masjid = draftSpot == nil ? (prayer.atMasjid ? prayer.mosqueName : nil)
                                      : draftSpot.flatMap { MasjidDetector.favoriteMasjid(near: $0) }
        let title = masjid ?? (draftSpot == nil ? address : draftAddress) ?? "Pinned on the map"
        return Button {
            guard let from = draftSpot ?? spot else { return }
            viewModel.startPicking(prayer, at: from, recorded: prayer.recordedSpot ?? spot)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: masjid != nil ? "building.columns" : "mappin.and.ellipse")
                    .foregroundStyle(masjid != nil ? Color.sage : .secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1).foregroundStyle(.primary)
                    if draftSpot != nil {
                        Text("moved · Save to keep it").font(.caption).foregroundStyle(Color.green)
                    }
                }
                Spacer(minLength: 0)
                Text("Change").font(.subheadline).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(draftSpot != nil ? Color.green.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        if timeChanged { prayerViewModel.editPrayerTime(prayer, to: draftTime) }   // keeps the recorded time
        if let draftSpot { prayerViewModel.movePrayer(prayer, to: draftSpot) }    // keeps the recorded spot
        draftSpot = nil
        viewModel.refreshPins()   // colour follows the score, the pin follows the spot
        viewModel.setSpotMode(.browse)
        viewModel.focus(on: prayer, sheetFraction: viewModel.pageFraction)
    }
}

/// One prayer at the spot: name, when it was prayed and where in its window, and the score.
struct PrayerSpotRow: View {
    let prayer: PrayerModel

    private var icon: String { prayerSymbol(prayer.name) }
    /// "12 min in" / "1h 20m in" — how far into the prayer window it was prayed.
    private var intoWindow: String? {
        guard let at = prayer.timeAtComplete else { return nil }
        let secs = at.timeIntervalSince(prayer.startTime)
        if secs < 0 { return "before it started" }
        if at > prayer.endTime { return "after it ended" }
        let m = Int(secs / 60)
        return m < 60 ? "\(m) min in" : "\(m / 60)h \(m % 60)m in"
    }
    private var window: String {
        "\(prayer.startTime.formatted(date: .omitted, time: .shortened)) – \(prayer.endTime.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prayer.displayName).font(.body.weight(.medium))
                    if let at = prayer.timeAtComplete {
                        Text("prayed \(at.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(window)
                    if let intoWindow { Text("·"); Text(intoWindow) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if prayer.atMasjid, let masjid = prayer.mosqueName {
                    Label(masjid, systemImage: "building.columns")
                        .font(.caption)
                        .foregroundStyle(Color.sage)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    ScoreDot(score: prayer.numberScore)
                    Text(prayer.numberScore.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                if let words = prayer.gradeWord {
                    Text(words).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The score's colour as a dot, same scale as the pins and the app.
private struct ScoreDot: View {
    let score: Double?
    var color: Color {
        PrayerScoring.color(for: score)
    }
    var body: some View { Circle().fill(color).frame(width: 9, height: 9) }
}
