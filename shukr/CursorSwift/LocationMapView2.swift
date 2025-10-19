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
class LocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate { //locmanflag used in map. -- cant merge with other cuz of the sharedtarget. starts yelling at us with PrayerModel.
    @Published var selectedPrayer: PrayerModel?
    @Published var selectedClusterPrayers: [PrayerModel]?
    @Published var mapType: MKMapType = .standard
    @Published var prayers: [PrayerModel] = [] // Holds all prayers with valid coordinates
    @Published var filteredPrayers: [PrayerModel] = [] // Holds prayers after applying filters
    @Published var visiblePrayerCount: Int = 0
    @Published var isAtMecca: Bool = false
    let meccaCoordinate = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    // Default filter values
    let defaultStartDate: Date
    let defaultEndDate: Date
    let defaultPrayerNames: Set<String> = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"]

    @Published var selectedStartDate: Date
    @Published var selectedEndDate: Date
    @Published var selectedPrayerNames: Set<String>

    // Variable to control annotation visibility
    @Published var showPrayers: Bool = false

    // Variables for Qibla calculation
    @Published var mapHeading: Double = 0
    @Published var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    @Published var qiblaDirection: Double = 0

    var filtersActive: Bool {
        selectedStartDate != defaultStartDate ||
        selectedEndDate != defaultEndDate ||
        selectedPrayerNames != defaultPrayerNames
    }

    private let locationManager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?

    var mapView: MKMapView?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        // Initialize default dates
        self.defaultEndDate = Date()
//        self.defaultStartDate = Calendar.current.date(byAdding: .month, value: -1, to: defaultEndDate) ?? defaultEndDate
        let currentYear = Calendar.current.component(.year, from: Date())
        self.defaultStartDate = Calendar.current.date(from: DateComponents(year: currentYear, month: 1, day: 1)) ?? defaultEndDate

        // Set initial selected dates to defaults
        self.selectedStartDate = self.defaultStartDate
        self.selectedEndDate = self.defaultEndDate
        self.selectedPrayerNames = self.defaultPrayerNames

        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = /*kCLLocationAccuracyBest*/ kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 40 // only update if user moves ≥ 10 meters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func setupBindings() {
        Publishers.CombineLatest4(
            $prayers,
            $selectedStartDate,
            $selectedEndDate,
            $selectedPrayerNames
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] (prayers, startDate, endDate, prayerNames) in
            guard let self = self else { return }
            self.filteredPrayers = prayers.filter { prayer in
                let startTime = prayer.startTime
                return startTime >= startDate && startTime <= endDate &&
                    prayerNames.contains(prayer.name)
            }
            // Update annotations
            self.mapView?.delegate?.mapView?(self.mapView!, regionDidChangeAnimated: false)
        }
        .store(in: &cancellables)

        // Observe showPrayers to update annotations when it changes
        $showPrayers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Update annotations
                self.mapView?.delegate?.mapView?(self.mapView!, regionDidChangeAnimated: false)
            }
            .store(in: &cancellables)
    }

    func showUserLocation() {
        if let location = locationManager.location {
            userLocation = location.coordinate
        }
    }

    // CL Location Manager Delegate methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // No automatic following
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            manager.stopUpdatingLocation()
        }
    }

    // Function to calculate Qibla direction based on map heading and center coordinate
    func updateQiblaDirection() {
        let meccaLatitude = 21.4225
        let meccaLongitude = 39.8262

        let centerLat = centerCoordinate.latitude * .pi / 180
        let centerLong = centerCoordinate.longitude * .pi / 180
        let meccaLat = meccaLatitude * .pi / 180
        let meccaLong = meccaLongitude * .pi / 180

        let y = sin(meccaLong - centerLong)
        let x = cos(centerLat) * tan(meccaLat) - sin(centerLat) * cos(meccaLong - centerLong)

        var bearing = atan2(y, x) * 180 / .pi
        bearing = (bearing + 360).truncatingRemainder(dividingBy: 360)

        // Instead of subtracting mapHeading, just store the bearing:
        DispatchQueue.main.async {
            withAnimation {
                self.qiblaDirection = bearing
            }
        }
    }
    
    // helper function to determine if mecca annotation is in our circleWithArrowOverlay
    func overlayRadiusInMeters(for mapView: MKMapView, overlayRadiusPoints: CGFloat = 100) -> CLLocationDistance {
        let centerPoint = mapView.center
        let edgePoint = CGPoint(x: centerPoint.x, y: centerPoint.y - overlayRadiusPoints)
        let centerCoordinate = mapView.centerCoordinate
        let edgeCoordinate = mapView.convert(edgePoint, toCoordinateFrom: mapView)
        let centerLocation = CLLocation(latitude: centerCoordinate.latitude, longitude: centerCoordinate.longitude)
        let edgeLocation = CLLocation(latitude: edgeCoordinate.latitude, longitude: edgeCoordinate.longitude)
        return centerLocation.distance(from: edgeLocation)
    }
    func updateMeccaProximity(using mapView: MKMapView) {
        let overlayRadius = overlayRadiusInMeters(for: mapView)  // default: 100 points radius
        let centerLocation = CLLocation(latitude: mapView.centerCoordinate.latitude, longitude: mapView.centerCoordinate.longitude)
        let meccaLocation = CLLocation(latitude: meccaCoordinate.latitude, longitude: meccaCoordinate.longitude)
        
        DispatchQueue.main.async {
            withAnimation {
                self.isAtMecca = centerLocation.distance(from: meccaLocation) < overlayRadius
            }
        }
    }
    
    /// Returns the shortest signed difference between two angles in degrees,
    /// guaranteed to be in the range -180...180.
    func angleDifference(from: Double, to: Double) -> Double {
        // Example: from = qiblaDirection, to = deviceHeading
        var diff = (from - to).truncatingRemainder(dividingBy: 360)
        if diff < -180 { diff += 360 }
        if diff > 180  { diff -= 360 }
        return diff
    }


}

// MARK: - MapView
struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: LocationViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()

        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.mapType = viewModel.mapType
        mapView.isRotateEnabled = false /*true*/
//        mapView.userTrackingMode = .followWithHeading
//        mapView.showsCompass = true    // Show compass
//        mapView.showsUserTrackingButton = true
        
//        let initialRegion = MKCoordinateRegion(
//            center: CLLocationCoordinate2D(latitude: 21.4225+3, longitude: 39.8262), //mecca with slight offset for pin to seem in center
//            span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
//        )
//        mapView.setRegion(initialRegion, animated: false)

        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        mapView.register(MeccaMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "MeccaAnnotationView")
        
        viewModel.mapView = mapView

        // Add Mecca annotation
        let meccaAnnotation = MeccaAnnotation()
        meccaAnnotation.coordinate = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)
        meccaAnnotation.title = "Mecca"
        mapView.addAnnotation(meccaAnnotation)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.mapType = viewModel.mapType

        // No need to update annotations here; handled by Coordinator

        if let userLocation = viewModel.userLocation {
            let span = mapView.region.span
            let region = MKCoordinateRegion(center: userLocation, span: span)
            mapView.setRegion(region, animated: true)
            viewModel.userLocation = nil
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        var currentAnnotations: [MKAnnotation] = [] // Keep track of current annotations

        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                // We’ll still need to update the centerCoordinate:
                self.parent.viewModel.centerCoordinate = mapView.centerCoordinate
                
                // We’ll still call updateQiblaDirection so that we compute the bearing
                self.parent.viewModel.updateQiblaDirection()

                // Update proximity based on the current zoom level
                self.parent.viewModel.updateMeccaProximity(using: mapView)
            }
            self.updateAnnotations(for: mapView.visibleMapRect)
        }


        func updateAnnotations(for visibleMapRect: MKMapRect) {
            // Remove existing annotations except Mecca
            let annotationsToRemove = currentAnnotations.filter { !($0 is MeccaAnnotation) }
            mapView.removeAnnotations(annotationsToRemove)
            currentAnnotations.removeAll(where: { !($0 is MeccaAnnotation) })

            // Check if annotations should be shown
            guard parent.viewModel.showPrayers else {
                // Update visiblePrayerCount to 0 when prayers are hidden
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5){
                    self.parent.viewModel.visiblePrayerCount = 0
                }
                return
            }
            // Fetch prayers within the visible region
            let visiblePrayers = parent.viewModel.filteredPrayers.filter { prayer in
                let latitude = prayer.latPrayedAt!
                let longitude = prayer.longPrayedAt!
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                let point = MKMapPoint(coordinate)
                return visibleMapRect.contains(point)
            }

            // Update the visible prayer count
            parent.viewModel.visiblePrayerCount = visiblePrayers.count // Update count
            
            // Create and add new annotations
            let annotations = visiblePrayers.map { prayer -> CustomPrayerAnnotation in
                let annotation = CustomPrayerAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: prayer.latPrayedAt!, longitude: prayer.longPrayedAt!)
                annotation.title = prayer.name
                annotation.prayer = prayer
                return annotation
            }

            mapView.addAnnotations(annotations)
            currentAnnotations.append(contentsOf: annotations)
        }

        // Adjusted to use mapView from parent
        var mapView: MKMapView {
            return parent.viewModel.mapView!
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }

            // Custom view for Mecca annotation
            if annotation is MeccaAnnotation {
                let identifier = "MeccaAnnotationView"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier, for: annotation)
                return annotationView
            }

            let identifier: String

            if annotation is MKClusterAnnotation {
                identifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
            } else {
                identifier = MKMapViewDefaultAnnotationViewReuseIdentifier
            }

            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier, for: annotation)

            if let clusterAnnotationView = annotationView as? MKMarkerAnnotationView, annotation is MKClusterAnnotation {
                clusterAnnotationView.markerTintColor = .blue
                clusterAnnotationView.glyphText = "\( (annotation as! MKClusterAnnotation).memberAnnotations.count)"
                clusterAnnotationView.canShowCallout = true
                return clusterAnnotationView
            }

            if let markerAnnotationView = annotationView as? MKMarkerAnnotationView {
                markerAnnotationView.markerTintColor = .white
                markerAnnotationView.glyphImage = UIImage(systemName: "mappin.square.fill")
                markerAnnotationView.canShowCallout = true
                markerAnnotationView.clusteringIdentifier = "cluster"
                return markerAnnotationView
            }

            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let annotation = view.annotation, !(annotation is MKUserLocation || annotation is MeccaAnnotation) {
                if let clusterAnnotation = annotation as? MKClusterAnnotation {
                    let memberPrayers = clusterAnnotation.memberAnnotations.compactMap { annotation in
                        (annotation as? CustomPrayerAnnotation)?.prayer
                    }
                    parent.viewModel.selectedClusterPrayers = memberPrayers
                } else if let customPrayerAnnotation = annotation as? CustomPrayerAnnotation, let prayer = customPrayerAnnotation.prayer {
                    parent.viewModel.selectedPrayer = prayer
                }
            }
        }
    }
}

// MARK: - ContentView
struct LocationMapContentView: View {
    @StateObject var viewModel = LocationViewModel()
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) var scenePhase

    // Fetch only prayers with non-nil coordinates
    @Query(filter: #Predicate<PrayerModel> { prayer in
        prayer.latPrayedAt != nil && prayer.longPrayedAt != nil
    }, sort: \PrayerModel.startTime) var prayers: [PrayerModel]
    @State private var mapViewRef: MKMapView?
    @State private var showFilterSheet = false

    @EnvironmentObject var sharedState: SharedStateClass
    @Environment(\.presentationMode) var presentationMode
    
    private func locationButtonAction(){
        if let mapView = mapViewRef {
            if let userLocation = mapView.userLocation.location?.coordinate {
                let currentSpan = mapView.region.span
                let maxSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                let closeSpan = /*viewModel.showPrayers ? MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02) : */MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)

                let newSpan: MKCoordinateSpan
                if currentSpan.latitudeDelta > maxSpan.latitudeDelta || currentSpan.longitudeDelta > maxSpan.longitudeDelta {
                    newSpan = closeSpan
                } else {
                    newSpan = currentSpan
                }
                let region = MKCoordinateRegion(center: userLocation, span: newSpan)
                mapView.setRegion(region, animated: true)
            }
        }
    }

    var body: some View {
        ZStack {
            MapView(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    viewModel.prayers = prayers // Set prayers in the viewModel
                    viewModel.setupBindings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        mapViewRef = viewModel.mapView
                        // Trigger initial annotation load
                        if let mapView = mapViewRef {
                            viewModel.mapView?.delegate?.mapView?(mapView, regionDidChangeAnimated: false)
                        }
                    }
                }

            // Qibla indicator when prayers are hidden
            VStack {
                Spacer()
                CircleWithArrowOverlay(degrees: viewModel.qiblaDirection, isAtMecca: viewModel.isAtMecca)
                    .padding()
                Spacer()
            }
            .allowsHitTesting(false) // So it doesn't interfere with map interactions
            .opacity(viewModel.showPrayers ? 0 : 1)

            // All The buttons:
            VStack{
                ZStack(alignment: .top){
                    //Close Button
                    HStack {
                        // Close button
                        Button(action: {
                            sharedState.allowQiblaHaptics = true
                            presentationMode.wrappedValue.dismiss()
                        }){
                            Text("Close")
                                .font(.body)
                                .padding()
                                .foregroundStyle(.blue)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        }
                        
                        Spacer()
                    }
//                    .border(.yellow)
                    
                    //Qibla / Prayers In Area Text:
                    HStack{
                        Spacer()
                        VStack{
                            if viewModel.showPrayers {
                                Text("Prayers in Area: \(viewModel.visiblePrayerCount)")
                                    .font(.subheadline)
//                                Text("\(viewModel.visiblePrayerCount)")
//                                    .font(.caption)
                            }
                            else{
//                                Text("Qibla: \(Int(round(viewModel.qiblaDirection + viewModel.mapHeading)))°")
                                //                        let diff = viewModel.angleDifference(from: viewModel.qiblaDirection, to: locationManager.compassHeading)
  
                                Text("""
                                Qibla: \(envLocationManager.qibla.aligned
                                    ? "Facing Mecca 🕋"
                                    : (viewModel.angleDifference(
                                        from: viewModel.qiblaDirection,
                                        to: envLocationManager.compassHeading
                                      ) < 0
                                      ? "Turn left ←"
                                      : "Turn right →"
                                    )
                                )
                                """)
                                .font(.subheadline)
                                .font(.subheadline)


//                                Text("Qibla: \(
//                                    envLocationManager.qibla.aligned
//                                    ? "Facing Mecca 🕋"
//                                    : viewModel.angleDifference(from: viewModel.qiblaDirection, to: envLocationManager.compassHeading) < 0
//                                    ? "Turn left ←"
//                                    : "Turn right →")"
//                                )
//                                .font(.subheadline)
                            }
                        }
                        .foregroundStyle(.black)
                        .padding()
                        .background(Color.white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(!viewModel.showPrayers && envLocationManager.qibla.aligned ? Color.green : Color.clear, lineWidth: 2)
                        )
                        .shadow(radius: 2)
                        Spacer()
                    }
                    .transition(.opacity)
//                    .border(.red)
                    
                    
                    //Side Buttons:
                    HStack {

                        Spacer()

                        VStack(spacing: 6) {
                            // Map layers button
                            Button(action: {
                                viewModel.mapType = viewModel.mapType == .standard ? .hybrid : .standard
                            }) {
                                Image(systemName: "map")
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                            }

                            // Location button
                            Button(action: {
                                locationButtonAction()
                            }) {
                                Image(systemName: "location")
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                            }

                            // Show/Hide Prayers button
                            Button(action: {
                                withAnimation{
                                    viewModel.showPrayers.toggle()
                                    sharedState.allowQiblaHaptics.toggle()
                                    if !viewModel.showPrayers {
                                        locationButtonAction()
                                    }
                                }
                            }) {
                                Image(systemName: viewModel.showPrayers ? "mappin.circle.fill" : "mappin.circle")
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(.blue)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                            }
                            
                            // Filter button with indication
                            Button(action: {
                                showFilterSheet = true
                            }) {
                                Image(systemName: viewModel.filtersActive ? "line.horizontal.3.decrease.circle.fill" : "line.horizontal.3.decrease.circle")
                                    .resizable()
                                    .frame(width: 14, height: 14)
                                    .foregroundColor(viewModel.filtersActive ? .white : .blue)
                                    .padding()
                                    .background(viewModel.filtersActive ? Color.blue : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(radius: 2)
                            }
                            .opacity(viewModel.showPrayers ? 1 : 0)

                        }
                    }
//                    .border(.brown)


                }
                .padding(.horizontal, 10)
                .padding(.top, 6)


                Spacer()
            }
            
        }
        .sheet(item: $viewModel.selectedPrayer) { prayer in
            PrayerDetailView(prayer: prayer)
        }
        .sheet(isPresented: Binding<Bool>(
            get: { viewModel.selectedClusterPrayers != nil },
            set: { if !$0 { viewModel.selectedClusterPrayers = nil } }
        )) {
            if let prayers = viewModel.selectedClusterPrayers {
                ClusterPrayersDetailView(prayers: prayers)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterView(
                selectedStartDate: $viewModel.selectedStartDate,
                selectedEndDate: $viewModel.selectedEndDate,
                selectedPrayerNames: $viewModel.selectedPrayerNames,
                defaultStartDate: viewModel.defaultStartDate,
                defaultEndDate: viewModel.defaultEndDate,
                defaultPrayerNames: viewModel.defaultPrayerNames
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                if let mapView = mapViewRef {
                    if let userLocation = mapView.userLocation.location?.coordinate {
                        let currentSpan = mapView.region.span
                        let maxSpan = MKCoordinateSpan(latitudeDelta: 0.15, longitudeDelta: 0.15)
                        let closeSpan = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)

                        let newSpan: MKCoordinateSpan
                        if currentSpan.latitudeDelta > maxSpan.latitudeDelta || currentSpan.longitudeDelta > maxSpan.longitudeDelta {
                            newSpan = closeSpan
                        } else {
                            newSpan = currentSpan
                        }
                        let region = MKCoordinateRegion(center: userLocation, span: newSpan)
                        mapView.setRegion(region, animated: true)
                    }
                }
            }
        }
        .onChange(of: scenePhase) {_, newScenePhase in
            if newScenePhase == .background {
                sharedState.allowQiblaHaptics = true
                presentationMode.wrappedValue.dismiss()
            }
        }
        .toolbar(.hidden, for:.navigationBar)
    }
}

// MARK: - CircleWithArrowOverlay
struct CircleWithArrowOverlay: View {
    @EnvironmentObject var locationManager: EnvLocationManager
    @EnvironmentObject var sharedState: SharedStateClass
    var degrees: Double
    var isAtMecca: Bool
    
    var body: some View {
        ZStack {
            // Change the circle's color based on isAtMecca:
            Circle()
                .stroke(lineWidth: isAtMecca || locationManager.qibla.aligned ? 4 : 2)
                .frame(width: 200, height: 200)
                .foregroundColor(isAtMecca || locationManager.qibla.aligned ? .green : .white)
                .shadow(color: isAtMecca || locationManager.qibla.aligned ? .white.opacity(0.7) : .black.opacity(0.1), radius: 10, x: 0, y: 0)
                .animation(.default, value: locationManager.qibla.aligned)

            // Only show the arrows if we're not at Mecca
            if !isAtMecca {
                Image(systemName: "arrowtriangle.up.fill")
                    .resizable()
                    .foregroundColor(locationManager.qibla.aligned ? .green : .white)
                    .frame(width: 20, height: 20)
                    .offset(y: -110)
                    .rotationEffect(.degrees(degrees))
                    .animation(.default, value: locationManager.qibla.aligned)

                // second (compass) arrow using your locationManager.
                // This uses the compassHeading from your environment object.
                Image(systemName: "chevron.up")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(locationManager.qibla.aligned ? .green : Color(.systemBlue))
                    .background(
                        Circle() // to increase tappable area
                            .fill(Color.white.opacity(0.001))
                            .frame(width: 44, height: 44)
                    )
                    .shadow(radius: 2)
//                    .opacity(0.7)
                    .offset(y: -20)
                    .rotationEffect(Angle(degrees: locationManager.qibla.aligned ? degrees : locationManager.compassHeading))
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
                .foregroundColor(locationManager.qibla.aligned ? .green : .primary)
                .background(
                    Circle() // this is to increase tappable aread
                        .fill(Color.white.opacity(0.001))
                        .frame(width: 44, height: 44)
                )
                .opacity(0.7)
                .offset(y: -80)
//                            .rotationEffect(Angle(degrees: locationManager.qibla.aligned ? 0 : locationManager.qibla.heading))
                .rotationEffect(Angle(degrees: locationManager.compassHeading))
                .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.1), value: locationManager.qibla.aligned)
//                            .onChange(of: locationManager.qibla.aligned) { _, newIsAligned in
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
struct PrayerDetailView: View {
    let prayer: PrayerModel

    var body: some View {
        VStack(spacing: 20) {
            Text(prayer.name)
                .font(.largeTitle)
                .bold()

            if let latitude = prayer.latPrayedAt, let longitude = prayer.longPrayedAt {
                Map(coordinateRegion: .constant(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))
                .frame(height: 200)
                .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Start Time: \(prayer.startTime.formatted(date: .abbreviated, time: .shortened))")
                Text("End Time: \(prayer.endTime.formatted(date: .abbreviated, time: .shortened))")
                if let timeAtComplete = prayer.timeAtComplete {
                    Text("Completed At: \(timeAtComplete.formatted(date: .abbreviated, time: .shortened))")
                }
                if let numberScore = prayer.numberScore {
                    Text("Performance Score: \(numberScore, specifier: "%.1f")")
                }
                if let englishScore = prayer.englishScore {
                    Text("Feedback: \(englishScore)")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            Spacer()
        }
        .padding()
    }
}

// MARK: - ClusterPrayersDetailView
struct ClusterPrayersDetailView: View {
    let prayers: [PrayerModel]

    var body: some View {
        NavigationView {
            VStack {
                if let centerCoordinate = getClusterCenterCoordinate() {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(
                        center: centerCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )), annotationItems: prayers) { prayer in
                        MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: prayer.latPrayedAt!, longitude: prayer.longPrayedAt!)) {
                            Circle()
                                .strokeBorder(Color.blue, lineWidth: 2)
                                .frame(width: 10, height: 10)
                        }
                    }
                    .frame(height: 200)
                    .cornerRadius(10)
                }

                Text("You have \(prayers.count) prayers here")
                    .font(.headline)
                    .padding()

                List(prayers) { prayer in
                    VStack(alignment: .leading) {
                        Text("\(prayer.name)")
                            .font(.headline)
                        if let timeAtComplete = prayer.timeAtComplete {
                            Text("@ \(timeAtComplete.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let latitude = prayer.latPrayedAt, let longitude = prayer.longPrayedAt {
                            Text("Location: \(latitude), \(longitude)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        if let engScore = prayer.englishScore {
                            Text("\(engScore)")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Prayers in Area")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // Helper function to calculate the center coordinate of the cluster
    func getClusterCenterCoordinate() -> CLLocationCoordinate2D? {
        let coordinates = prayers.compactMap { prayer -> CLLocationCoordinate2D? in
            if let latitude = prayer.latPrayedAt, let longitude = prayer.longPrayedAt {
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            return nil
        }

        guard !coordinates.isEmpty else { return nil }

        let totalLatitude = coordinates.reduce(0) { $0 + $1.latitude }
        let totalLongitude = coordinates.reduce(0) { $0 + $1.longitude }
        let centerLatitude = totalLatitude / Double(coordinates.count)
        let centerLongitude = totalLongitude / Double(coordinates.count)

        return CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
    }
}
