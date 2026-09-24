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
    /// The pin (one prayer) or cluster (several) the user tapped; drives the half sheet.
    @Published var selection: PrayerSpotSelection?
    @Published var mapType: MKMapType = .standard
    @Published var showPrayers: Bool = false
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
    var filtersActive: Bool {
        selectedStartDate != defaultStartDate || selectedEndDate != defaultEndDate || selectedPrayerNames != defaultPrayerNames
    }

    /// Every prayer with coordinates (set by the view from its @Query) and the filtered set the
    /// map shows. The coordinator subscribes to `filteredPrayers` and rebuilds its pins once
    /// per change — MapKit clusters and culls them itself from there.
    @Published var prayers: [PrayerModel] = []
    @Published private(set) var filteredPrayers: [PrayerModel] = []

    weak var mapView: MKMapView?
    private var cancellables = Set<AnyCancellable>()

    init() {
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        defaultStartDate = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        defaultEndDate = now
        selectedStartDate = defaultStartDate
        selectedEndDate = defaultEndDate
        selectedPrayerNames = defaultPrayerNames

        Publishers.CombineLatest4($prayers, $selectedStartDate, $selectedEndDate, $selectedPrayerNames)
            .map { prayers, start, end, names in
                prayers.filter { $0.startTime >= start && $0.startTime <= end && names.contains($0.name) }
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
        guard let score = prayer.numberScore else { return .systemGray }
        if score >= 0.5 { return .systemGreen }
        if score >= 0.25 { return .systemYellow }
        return .systemRed
    }
}

/// Where the user's dot is on screen, updated continuously while the map moves so the qibla
/// ring can sit on the dot instead of the screen centre. @Observable: only the ring reads it.
@Observable final class MapAnchor {
    var userPoint: CGPoint? = nil
    /// Zoomed out past ~50 km across: the ring means nothing at that scale and hides.
    var zoomedOut = false
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

/// The MKMapView. North-up on purpose: the compass on a phone is often off, and a north-up map
/// with the line to the Kaaba drawn on it lets the user line up with the buildings around
/// them and know the direction for a fact. The compass only helps them turn.
struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: LocationViewModel
    var envLocation: EnvLocationManager
    var anchor: MapAnchor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.isRotateEnabled = false        // north-up, see above
        mapView.isPitchEnabled = false
        mapView.mapType = viewModel.mapType
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
            mapView.setRegion(MKCoordinateRegion(center: here, span: Coordinator.closeSpan), animated: false)
            context.coordinator.didCentreOnUser = true
            context.coordinator.userMoved(to: here, on: mapView)
        }
        context.coordinator.subscribe(to: viewModel, mapView: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if mapView.mapType != viewModel.mapType { mapView.mapType = viewModel.mapType }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let closeSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)   // ~900 m across: your block, not your borough
        var parent: MapView
        var didCentreOnUser = false
        private var prayerAnnotations: [CustomPrayerAnnotation] = []
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
            var count = 0
            for annotation in mapView.annotations(in: mapView.visibleMapRect) {
                if annotation is CustomPrayerAnnotation { count += 1 }
                else if let cluster = annotation as? MKClusterAnnotation { count += cluster.memberAnnotations.count }
            }
            if parent.viewModel.visiblePrayerCount != count { parent.viewModel.visiblePrayerCount = count }
        }

        /// The user moved: redraw the great-circle line to the Kaaba and update the bearing.
        func userMoved(to coordinate: CLLocationCoordinate2D, on mapView: MKMapView) {
            let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let origin = lineOrigin, origin.distance(from: here) < 25 { return }   // GPS jitter
            lineOrigin = here
            if let old = qiblaLine { mapView.removeOverlay(old) }
            let line = MKGeodesicPolyline(coordinates: [coordinate, LocationViewModel.meccaCoordinate], count: 2)
            mapView.addOverlay(line, level: .aboveRoads)
            qiblaLine = line
            let bearing = LocationViewModel.bearingToMecca(from: coordinate)
            if abs(parent.viewModel.qiblaBearing - bearing) > 0.5 { parent.viewModel.qiblaBearing = bearing }
        }

        /// The ring sits on the user's dot: report where the dot is on screen. Called on every
        /// frame of a pan/zoom (`mapViewDidChangeVisibleRegion`) and on every fix.
        private func updateAnchor(on mapView: MKMapView) {
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
                mapView.setRegion(MKCoordinateRegion(center: coordinate, span: Self.closeSpan), animated: true)
            }
            userMoved(to: coordinate, on: mapView)
            updateAnchor(on: mapView)
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateAnchor(on: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateVisibleCount(on: mapView)
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
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: annotation) as! MKMarkerAnnotationView
                view.markerTintColor = .systemGreen
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.canShowCallout = false
                view.displayPriority = .required
                return view
            }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier, for: annotation) as! MKMarkerAnnotationView
            if let prayer = (annotation as? CustomPrayerAnnotation)?.prayer {
                view.markerTintColor = LocationViewModel.markerColor(for: prayer)
            }
            view.glyphImage = UIImage(systemName: "hands.and.sparkles.fill") ?? UIImage(systemName: "mappin")
            view.clusteringIdentifier = "prayer"
            view.canShowCallout = false
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            defer { mapView.deselectAnnotation(view.annotation, animated: false) }   // so the same pin can be tapped again
            guard let annotation = view.annotation else { return }
            if let cluster = annotation as? MKClusterAnnotation {
                let prayers = cluster.memberAnnotations.compactMap { ($0 as? CustomPrayerAnnotation)?.prayer }
                parent.viewModel.selection = PrayerSpotSelection(prayers: prayers)
            } else if let prayer = (annotation as? CustomPrayerAnnotation)?.prayer {
                parent.viewModel.selection = PrayerSpotSelection(prayers: [prayer])
            }
        }
    }
}

// MARK: - ContentView

struct LocationMapContentView: View {
    @StateObject private var viewModel = LocationViewModel()
    @EnvironmentObject var compass: CompassState
    @EnvironmentObject var envLocation: EnvLocationManager
    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.dismiss) private var dismiss

    /// Every prayer with a recorded spot.
    @Query(filter: #Predicate<PrayerModel> { $0.latPrayedAt != nil && $0.longPrayedAt != nil },
           sort: \PrayerModel.startTime) private var prayers: [PrayerModel]
    @State private var showFilterSheet = false
    @State private var anchor = MapAnchor()

    private func centreOnUser() {
        guard let mapView = viewModel.mapView,
              let here = mapView.userLocation.location?.coordinate ?? envLocation.userLocation?.coordinate else { return }
        let current = mapView.region.span
        let zoomedOut = current.latitudeDelta > 0.012 || current.longitudeDelta > 0.012
        let span = zoomedOut ? MapView.Coordinator.closeSpan : current
        mapView.setRegion(MKCoordinateRegion(center: here, span: span), animated: true)
    }

    /// The compass pill: aligned, or which way and how far to turn.
    private var compassHint: String {
        if compass.qibla.aligned { return "Facing Mecca 🕋" }
        let diff = signedAngleDifference(from: viewModel.qiblaBearing, to: compass.heading)
        let degrees = Int(abs(diff).rounded())
        return diff < 0 ? "← Turn left \(degrees)°" : "Turn right \(degrees)° →"
    }

    var body: some View {
        ZStack {
            MapView(viewModel: viewModel, envLocation: envLocation, anchor: anchor)
                .ignoresSafeArea()
                .onAppear { viewModel.prayers = prayers }
                .onChange(of: prayers.count) { _, _ in viewModel.prayers = prayers }

            // Qibla ring, sitting on the user's dot: the green line is the direction, the
            // ring's arrow repeats it and the chevron follows the compass.
            AnchoredQiblaRing(anchor: anchor, degrees: viewModel.qiblaBearing, isAtMecca: viewModel.isAtMecca)
                .opacity(viewModel.showPrayers ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: viewModel.showPrayers)

            // Facing Mecca: the whole screen edge glows green.
            AlignedEdgeGlow(on: compass.qibla.aligned && !viewModel.showPrayers)

            VStack {
                ZStack(alignment: .top) {
                    HStack {
                        Button {
                            sharedState.allowQiblaHaptics = true
                            dismiss()
                        } label: {
                            Text("Close").font(.body)
                        }
                        .buttonStyle(MapPill())
                        Spacer()
                    }

                    // Status pill: compass hint in qibla mode, count in prayers mode.
                    HStack {
                        Spacer()
                        Text(viewModel.showPrayers ? "Prayers in area: \(viewModel.visiblePrayerCount)" : compassHint)
                            .monospacedDigit()
                            .font(.subheadline)
                            .foregroundStyle(.black)
                            .padding()
                            .background(Color.white.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(!viewModel.showPrayers && compass.qibla.aligned ? Color.green : Color.clear, lineWidth: 2))
                            .shadow(radius: 2)
                        Spacer()
                    }

                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Button { viewModel.mapType = viewModel.mapType == .standard ? .hybrid : .standard } label: {
                                Image(systemName: "map")
                            }
                            .buttonStyle(MapPill())
                            Button { centreOnUser() } label: {
                                Image(systemName: "location")
                            }
                            .buttonStyle(MapPill())
                            Button {
                                withAnimation {
                                    viewModel.showPrayers.toggle()
                                    sharedState.allowQiblaHaptics.toggle()
                                }
                                if !viewModel.showPrayers { centreOnUser() }
                            } label: {
                                Image(systemName: viewModel.showPrayers ? "mappin.circle.fill" : "mappin.circle")
                            }
                            .buttonStyle(MapPill())
                            Button { showFilterSheet = true } label: {
                                Image(systemName: viewModel.filtersActive ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                            }
                            .buttonStyle(MapPill(filled: viewModel.filtersActive))
                            .opacity(viewModel.showPrayers ? 1 : 0)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                Spacer()
            }
        }
        .sheet(item: $viewModel.selection) { selection in
            // Half sheet: the pin is already on the map behind it, so just the data. The map
            // stays usable underneath at the medium detent.
            PrayerSpotSheet(prayers: selection.prayers)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterView(selectedStartDate: $viewModel.selectedStartDate,
                       selectedEndDate: $viewModel.selectedEndDate,
                       selectedPrayerNames: $viewModel.selectedPrayerNames,
                       defaultStartDate: viewModel.defaultStartDate,
                       defaultEndDate: viewModel.defaultEndDate,
                       defaultPrayerNames: viewModel.defaultPrayerNames)
        }
        .toolbar(.hidden, for: .navigationBar)
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
            CircleWithArrowOverlay(degrees: degrees, isAtMecca: isAtMecca, ringHidden: anchor.zoomedOut)
                .position(anchor.userPoint ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The map's floating buttons: white pill, green glyph (filled: green pill, white glyph).
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
                    .rotationEffect(.degrees(start - 90))   // trim starts at 3 o'clock; put it at `start`
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
                    .rotationEffect(.degrees(degrees))
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
                    .rotationEffect(Angle(degrees: compass.qibla.aligned ? degrees : compass.heading))
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
struct CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                    .foregroundColor(configuration.isOn ? .blue : .primary)
                configuration.label
            }
        }
    }
}

// MARK: - FilterView
struct FilterView: View {
    @Binding var selectedStartDate: Date
    @Binding var selectedEndDate: Date
    @Binding var selectedPrayerNames: Set<String>

    let defaultStartDate: Date
    let defaultEndDate: Date
    let defaultPrayerNames: Set<String>

    @Environment(\.dismiss) var dismiss

    let allPrayerNames = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date Range")) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Start Date")
                                .font(.caption)
                            DatePicker("", selection: $selectedStartDate, in: ...selectedEndDate, displayedComponents: [.date])
                                .labelsHidden()
                                .onChange(of: selectedStartDate) {_, newValue in
                                    if selectedStartDate > selectedEndDate {
                                        selectedEndDate = selectedStartDate
                                    }
                                }
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("End Date")
                                .font(.caption)
                            DatePicker("", selection: $selectedEndDate, in: selectedStartDate...Date(), displayedComponents: [.date])
                                .labelsHidden()
                                .onChange(of: selectedEndDate) {_, newValue in
                                    if selectedEndDate < selectedStartDate {
                                        selectedStartDate = selectedEndDate
                                    }
                                }
                        }
                    }
                }

                Section(header: Text("Prayers")) {
                    ForEach(allPrayerNames, id: \.self) { prayerName in
                        Toggle(isOn: Binding(
                            get: { selectedPrayerNames.contains(prayerName) },
                            set: { isSelected in
                                if isSelected {
                                    selectedPrayerNames.insert(prayerName)
                                } else {
                                    selectedPrayerNames.remove(prayerName)
                                }
                            }
                        )) {
                            Text(prayerName)
                        }
                        .toggleStyle(CheckboxStyle())
                    }
                }
            }
            .navigationBarTitle("Filter Prayers", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Reset") {
                    selectedStartDate = defaultStartDate
                    selectedEndDate = defaultEndDate
                    selectedPrayerNames = defaultPrayerNames
                },
                trailing: Button("Done") {
                    dismiss()
                }
            )
        }
    }
}

// MARK: - PrayerDetailView
/// What was tapped on the map: the prayers at one pin or in one cluster.
struct PrayerSpotSelection: Identifiable {
    let id = UUID()
    let prayers: [PrayerModel]
}

// MARK: - PrayerSpotSheet

/// The half sheet for a tapped pin or cluster: a headline, per-prayer counts and the average
/// score for a cluster, then every prayer newest first grouped by day with when it was prayed,
/// where that fell in its window, and its score.
struct PrayerSpotSheet: View {
    let prayers: [PrayerModel]

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
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prayers.count == 1 ? "1 prayer here" : "\(prayers.count) prayers here")
                            .font(.title3.weight(.semibold))
                        if prayers.count > 1 {
                            Text(countsLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let avg = averageScore, prayers.count > 1 {
                            HStack(spacing: 6) {
                                ScoreDot(score: avg)
                                Text("Average score \(Int((avg * 100).rounded()))%")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                }

                ForEach(days, id: \.date) { day in
                    Section(zikrDayLabel(day.date)) {
                        ForEach(day.prayers) { prayer in
                            PrayerSpotRow(prayer: prayer)
                        }
                    }
                }
            }
            .fontDesign(.rounded)
            .navigationTitle("Prayer spot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// One prayer at the spot: name, when it was prayed and where in its window, and the score.
private struct PrayerSpotRow: View {
    let prayer: PrayerModel

    private var icon: String {
        switch prayer.name {
        case "Fajr": return "sunrise.fill"
        case "Dhuhr": return "sun.max.fill"
        case "Asr": return "sun.haze.fill"
        case "Maghrib": return "sunset.fill"
        case "Isha": return "moon.stars.fill"
        default: return "circle"
        }
    }
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
                    Text(prayer.name).font(.body.weight(.medium))
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
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    ScoreDot(score: prayer.numberScore)
                    Text(prayer.numberScore.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                if let words = prayer.englishScore {
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
        guard let score else { return .gray }
        if score >= 0.5 { return .green }
        if score >= 0.25 { return .yellow }
        return .red
    }
    var body: some View { Circle().fill(color).frame(width: 9, height: 9) }
}
