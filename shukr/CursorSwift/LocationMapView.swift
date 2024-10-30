//import SwiftUI
//import MapKit
//import CoreLocation
//
//// MARK: - Model
//struct StoredLocation: Identifiable {
//    let id = UUID()
//    let coordinate: CLLocationCoordinate2D
//    let timestamp: Date
//}
//
//class CustomAnnotation: MKPointAnnotation {
//    var storedLocation: StoredLocation?
//}
//
//// Wrapper for cluster locations
//struct ClusterLocationsWrapper: Identifiable {
//    let id = UUID()
//    let locations: [StoredLocation]
//}
//
//// MARK: - ViewModel
//class LocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
//    @Published var storedLocations: [StoredLocation] = []
//    @Published var selectedLocation: StoredLocation?
//    @Published var selectedClusterLocations: ClusterLocationsWrapper?
//    @Published var mapType: MKMapType = .standard
//
//    private let locationManager = CLLocationManager()
//    @Published var userLocation: CLLocationCoordinate2D?
//
//    var mapView: MKMapView?
//
//    override init() {
//        super.init()
//        locationManager.delegate = self
//        locationManager.desiredAccuracy = kCLLocationAccuracyBest
//        locationManager.requestWhenInUseAuthorization()
//        locationManager.startUpdatingLocation()
//    }
//
//    func addCurrentLocation() {
//        if let location = locationManager.location {
//            let newLocation = StoredLocation(coordinate: location.coordinate, timestamp: Date())
//            storedLocations.append(newLocation)
//        }
//    }
//
//    func showUserLocation() {
//        if let location = locationManager.location {
//            userLocation = location.coordinate  // This will trigger the map to center once
//        }
//    }
//
//    // CLLocationManagerDelegate methods
//    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//        // Don't update userLocation here anymore
//        // This prevents automatic following
//    }
//
//    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//        switch manager.authorizationStatus {
//        case .authorizedWhenInUse, .authorizedAlways:
//            manager.startUpdatingLocation()
//        default:
//            manager.stopUpdatingLocation()
//        }
//    }
//}
//
//// MARK: - MapView
//struct MapView: UIViewRepresentable {
//    @ObservedObject var viewModel: LocationViewModel
//
//    func makeCoordinator() -> Coordinator {
//        Coordinator(self)
//    }
//
//    func makeUIView(context: Context) -> MKMapView {
//        let mapView = MKMapView()
//        viewModel.mapView = mapView  // Store the reference
//
//        mapView.delegate = context.coordinator
//        mapView.showsUserLocation = true  // Keep this to show the blue dot
//        mapView.userTrackingMode = .none  // This ensures we don't follow the user
//        mapView.mapType = viewModel.mapType
//
//        // Set an initial region (e.g., United States)
//        let initialRegion = MKCoordinateRegion(
//            center: CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129),
//            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
//        )
//        mapView.setRegion(initialRegion, animated: false)
//
//        // Register annotation views
//        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
//        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
//
//        return mapView
//    }
//
//    func updateUIView(_ mapView: MKMapView, context: Context) {
//        // Update the map type
//        mapView.mapType = viewModel.mapType
//
//        // Remove all annotations
//        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
//
//        // Add annotations
//        let annotations = viewModel.storedLocations.map { location -> CustomAnnotation in
//            let annotation = CustomAnnotation()
//            annotation.coordinate = location.coordinate
//            annotation.title = "Location"
//            annotation.storedLocation = location
//            return annotation
//        }
//
//        mapView.addAnnotations(annotations)
//
//        // Only center on user location when explicitly requested
//        if let userLocation = viewModel.userLocation {
//            // Store current zoom level
//            let span = mapView.region.span
//            let region = MKCoordinateRegion(
//                center: userLocation,
//                span: span  // Maintain the current zoom level
//            )
//            mapView.setRegion(region, animated: true)
//            viewModel.userLocation = nil  // Reset so it doesn't keep centering
//        }
//    }
//
//    class Coordinator: NSObject, MKMapViewDelegate {
//        var parent: MapView
//
//        init(_ parent: MapView) {
//            self.parent = parent
//        }
//
//        // MKMapViewDelegate methods
//
//        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
//            // Don't customize the user location annotation
//            if annotation is MKUserLocation {
//                return nil
//            }
//
//            let identifier: String
//
//            if annotation is MKClusterAnnotation {
//                identifier = MKMapViewDefaultClusterAnnotationViewReuseIdentifier
//            } else {
//                identifier = MKMapViewDefaultAnnotationViewReuseIdentifier
//            }
//
//            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier, for: annotation)
//
//            if let clusterAnnotationView = annotationView as? MKMarkerAnnotationView, annotation is MKClusterAnnotation {
//                clusterAnnotationView.markerTintColor = .blue
//                clusterAnnotationView.glyphText = "\( (annotation as! MKClusterAnnotation).memberAnnotations.count)"
//                clusterAnnotationView.canShowCallout = true
//                return clusterAnnotationView
//            }
//
//            if let markerAnnotationView = annotationView as? MKMarkerAnnotationView {
//                markerAnnotationView.markerTintColor = .white
//                markerAnnotationView.glyphImage = UIImage(systemName: "mappin.square.fill")
//                markerAnnotationView.canShowCallout = true
//                markerAnnotationView.clusteringIdentifier = "cluster"
//                return markerAnnotationView
//            }
//
//            return nil
//        }
//
//        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
//            // Handle annotation selection
//            if let annotation = view.annotation, !(annotation is MKUserLocation) {
//                if let clusterAnnotation = annotation as? MKClusterAnnotation {
//                    // Handle cluster selection
//                    let memberLocations = clusterAnnotation.memberAnnotations.compactMap { annotation in
//                        if let customAnnotation = annotation as? CustomAnnotation {
//                            return customAnnotation.storedLocation
//                        }
//                        return nil
//                    }
//                    // Set the selected cluster locations in the view model
//                    parent.viewModel.selectedClusterLocations = ClusterLocationsWrapper(locations: memberLocations)
//                } else if let customAnnotation = annotation as? CustomAnnotation, let storedLocation = customAnnotation.storedLocation {
//                    // Handle single annotation selection
//                    parent.viewModel.selectedLocation = storedLocation
//                }
//            }
//        }
//    }
//
//    func centerOnUserLocation(_ mapView: MKMapView) {
//        if let userLocation = mapView.userLocation.location?.coordinate {
//            let span = mapView.region.span
//            let region = MKCoordinateRegion(
//                center: userLocation,
//                span: span
//            )
//            mapView.setRegion(region, animated: true)
//        }
//    }
//}
//
//// MARK: - ContentView
//struct LocationMapContentView: View {
//    @StateObject var viewModel = LocationViewModel()
//    @State private var mapViewRef: MKMapView?
//    @State private var showMapTypePicker = false  // Add this state
//
//    var body: some View {
//        ZStack {
//            MapView(viewModel: viewModel)
//                .edgesIgnoringSafeArea(.all)
//                .onAppear {
//                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                        mapViewRef = viewModel.mapView
//                    }
//                }
//
//            // Center-right buttons
//            GeometryReader { geometry in
//                VStack {
//                    Spacer()
//                        .frame(height: geometry.size.height * 0.3) // Position at about 1/3 down
//                    
//                    VStack(spacing: 10) {
//                        // Map layers button
//                        Button(action: {
//                            showMapTypePicker.toggle()
//                        }) {
//                            Image(systemName: "map.fill")
//                                .foregroundColor(.blue)
//                                .padding()
//                                .background(Color.white)
//                                .clipShape(RoundedRectangle(cornerRadius: 8))
//                                .shadow(radius: 2)
//                        }
//                        
//                        // Location button
//                        Button(action: {
//                            if let mapView = mapViewRef {
//                                if let userLocation = mapView.userLocation.location?.coordinate {
//                                    let span = mapView.region.span
//                                    let region = MKCoordinateRegion(
//                                        center: userLocation,
//                                        span: span
//                                    )
//                                    mapView.setRegion(region, animated: true)
//                                }
//                            }
//                        }) {
//                            Image(systemName: "location.fill")
//                                .foregroundColor(.blue)
//                                .padding()
//                                .background(Color.white)
//                                .clipShape(RoundedRectangle(cornerRadius: 8))
//                                .shadow(radius: 2)
//                        }
//                        
//                        // Add location button
//                        Button(action: viewModel.addCurrentLocation) {
//                            Image(systemName: "plus")
//                                .foregroundColor(.blue)
//                                .padding()
//                                .background(Color.white)
//                                .clipShape(RoundedRectangle(cornerRadius: 8))
//                                .shadow(radius: 2)
//                        }
//                    }
//                    .padding(.trailing, 20)
//                    
//                    Spacer()
//                }
//            }
//            
//            // Map type picker sheet
//            if showMapTypePicker {
//                VStack {
//                    Spacer()
//                    Picker("", selection: $viewModel.mapType) {
//                        Text("Standard").tag(MKMapType.standard)
//                        Text("Satellite").tag(MKMapType.satellite)
//                        Text("Hybrid").tag(MKMapType.hybrid)
//                    }
//                    .pickerStyle(SegmentedPickerStyle())
//                    .padding()
//                    .background(Color.white.opacity(0.8))
//                    .transition(.move(edge: .bottom))
//                }
//            }
//        }
//        .sheet(item: $viewModel.selectedLocation) { location in
//            LocationDetailView(location: location)
//        }
//        .sheet(item: $viewModel.selectedClusterLocations) { wrapper in
//            ClusterDetailView(locations: wrapper.locations)
//        }
//    }
//}
//
//// MARK: - LocationDetailView
//struct LocationDetailView: View {
//    let location: StoredLocation
//
//    var body: some View {
//        VStack(spacing: 20) {
//            Text("Location Details")
//                .font(.headline)
//            Text("Latitude: \(location.coordinate.latitude)")
//            Text("Longitude: \(location.coordinate.longitude)")
//            Text("Timestamp: \(location.timestamp.formatted(date: .numeric, time: .standard))")
//            Spacer()
//        }
//        .padding()
//    }
//}
//
//// MARK: - ClusterDetailView
//struct ClusterDetailView: View {
//    let locations: [StoredLocation]
//
//    var body: some View {
//        NavigationView {
//            List(locations) { location in
//                VStack(alignment: .leading) {
//                    Text("Latitude: \(location.coordinate.latitude)")
//                    Text("Longitude: \(location.coordinate.longitude)")
//                    Text("Timestamp: \(location.timestamp.formatted(date: .numeric, time: .standard))")
//                }
//            }
//            .navigationTitle("Cluster Items")
//            .navigationBarTitleDisplayMode(.inline)
//        }
//    }
//}
//
//
//#Preview {
//    LocationMapContentView()
//        .onAppear {
//            // Add some sample locations for the preview
//            let viewModel = LocationViewModel()
//            let sampleLocations = [
//                CLLocationCoordinate2D(latitude: 37.3352, longitude: -122.0096), // Apple Park
//                CLLocationCoordinate2D(latitude: 30.3350, longitude: -122.0094), // Near Apple Park
//                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)  // San Francisco
//            ]
//            
//            sampleLocations.forEach { coordinate in
//                viewModel.storedLocations.append(
//                    StoredLocation(
//                        coordinate: coordinate,
//                        timestamp: Date()
//                    )
//                )
//            }
//        }
//}


import SwiftUI
import MapKit
import CoreLocation

// MARK: - Model
struct StoredLocation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
}

class CustomAnnotation: MKPointAnnotation {
    var storedLocation: StoredLocation?
}

// Wrapper for cluster locations
struct ClusterLocationsWrapper: Identifiable {
    let id = UUID()
    let locations: [StoredLocation]
}

// MARK: - ViewModel
class LocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var storedLocations: [StoredLocation] = []
    @Published var selectedLocation: StoredLocation?
    @Published var selectedClusterLocations: ClusterLocationsWrapper?
    @Published var mapType: MKMapType = .standard

    private let locationManager = CLLocationManager()
    @Published var userLocation: CLLocationCoordinate2D?

    var mapView: MKMapView?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func addCurrentLocation() {
        if let location = locationManager.location {
            let newLocation = StoredLocation(coordinate: location.coordinate, timestamp: Date())
            storedLocations.append(newLocation)
        }
    }

    func showUserLocation() {
        if let location = locationManager.location {
            userLocation = location.coordinate  // This will trigger the map to center once
        }
    }

    // CLLocationManagerDelegate methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Don't update userLocation here anymore
        // This prevents automatic following
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            manager.stopUpdatingLocation()
        }
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
        viewModel.mapView = mapView  // Store the reference

        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true  // Keep this to show the blue dot
        mapView.userTrackingMode = .none  // This ensures we don't follow the user
        mapView.mapType = viewModel.mapType

        // Set an initial region (e.g., United States)
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.0902, longitude: -95.7129),
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
        )
        mapView.setRegion(initialRegion, animated: false)

        // Register annotation views
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update the map type
        mapView.mapType = viewModel.mapType

        // Remove all annotations
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        // Add annotations
        let annotations = viewModel.storedLocations.map { location -> CustomAnnotation in
            let annotation = CustomAnnotation()
            annotation.coordinate = location.coordinate
            annotation.title = "Location"
            annotation.storedLocation = location
            return annotation
        }

        mapView.addAnnotations(annotations)

        // Only center on user location when explicitly requested
        if let userLocation = viewModel.userLocation {
            // Store current zoom level
            let span = mapView.region.span
            let region = MKCoordinateRegion(
                center: userLocation,
                span: span  // Maintain the current zoom level
            )
            mapView.setRegion(region, animated: true)
            viewModel.userLocation = nil  // Reset so it doesn't keep centering
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        // MKMapViewDelegate methods

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Don't customize the user location annotation
            if annotation is MKUserLocation {
                return nil
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
            // Handle annotation selection
            if let annotation = view.annotation, !(annotation is MKUserLocation) {
                if let clusterAnnotation = annotation as? MKClusterAnnotation {
                    // Handle cluster selection
                    let memberLocations = clusterAnnotation.memberAnnotations.compactMap { annotation in
                        if let customAnnotation = annotation as? CustomAnnotation {
                            return customAnnotation.storedLocation
                        }
                        return nil
                    }
                    // Set the selected cluster locations in the view model
                    parent.viewModel.selectedClusterLocations = ClusterLocationsWrapper(locations: memberLocations)
                } else if let customAnnotation = annotation as? CustomAnnotation, let storedLocation = customAnnotation.storedLocation {
                    // Handle single annotation selection
                    parent.viewModel.selectedLocation = storedLocation
                }
            }
        }
    }
}

// MARK: - ContentView
struct LocationMapContentView: View {
    @StateObject var viewModel = LocationViewModel()
    @State private var mapViewRef: MKMapView?
    @State private var showMapTypePicker = false  // Add this state

    var body: some View {
        ZStack {
            MapView(viewModel: viewModel)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        mapViewRef = viewModel.mapView
                    }
                }

            // Top-right corner buttons
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 10) {
                        // Map layers button
                        Button(action: {
                            viewModel.mapType = viewModel.mapType == .standard ? .hybrid : .standard
                        }) {
                            Image(systemName: "map")
                                .foregroundColor(.blue)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        }
                        
                        // Location button
                        Button(action: {
                            if let mapView = mapViewRef {
                                if let userLocation = mapView.userLocation.location?.coordinate {
                                    let span = mapView.region.span
                                    let region = MKCoordinateRegion(
                                        center: userLocation,
                                        span: span
                                    )
                                    mapView.setRegion(region, animated: true)
                                }
                            }
                        }) {
                            Image(systemName: "location")
                                .foregroundColor(.blue)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        }
                        
                        // Add location button
                        Button(action: viewModel.addCurrentLocation) {
                            Image(systemName: "plus")
                                .foregroundColor(.blue)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .shadow(radius: 2)
                        }
                    }
//                    .padding(.top, 10) // Adjusts the vertical positioning from the top
                    .padding(.trailing, 10)
                }
                Spacer()
                
                // Map type picker at the bottom
//                if showMapTypePicker {
//                    VStack {
//                        Spacer()
//                        Picker("", selection: $viewModel.mapType) {
//                            Text("Standard").tag(MKMapType.standard)
//                            Text("Satellite").tag(MKMapType.satellite)
//                            Text("Hybrid").tag(MKMapType.hybrid)
//                        }
//                        .pickerStyle(SegmentedPickerStyle())
//                        .padding()
//                        .background(Color.white.opacity(0.8))
//                        .transition(.move(edge: .bottom))
//                    }
//                }
            }
        }
        .sheet(item: $viewModel.selectedLocation) { location in
            LocationDetailView(location: location)
        }
        .sheet(item: $viewModel.selectedClusterLocations) { wrapper in
            ClusterDetailView(locations: wrapper.locations)
        }
    }
}

// MARK: - LocationDetailView
struct LocationDetailView: View {
    let location: StoredLocation

    var body: some View {
        VStack(spacing: 20) {
            Text("Location Details")
                .font(.headline)
            Text("Latitude: \(location.coordinate.latitude)")
            Text("Longitude: \(location.coordinate.longitude)")
            Text("Timestamp: \(location.timestamp.formatted(date: .numeric, time: .standard))")
            Spacer()
        }
        .padding()
    }
}

// MARK: - ClusterDetailView
struct ClusterDetailView: View {
    let locations: [StoredLocation]

    var body: some View {
        NavigationView {
            List(locations) { location in
                VStack(alignment: .leading) {
                    Text("Latitude: \(location.coordinate.latitude)")
                    Text("Longitude: \(location.coordinate.longitude)")
                    Text("Timestamp: \(location.timestamp.formatted(date: .numeric, time: .standard))")
                }
            }
            .navigationTitle("Cluster Items")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    LocationMapContentView()
        .onAppear {
            // Add some sample locations for the preview
            let viewModel = LocationViewModel()
            let sampleLocations = [
                CLLocationCoordinate2D(latitude: 37.3352, longitude: -122.0096), // Apple Park
                CLLocationCoordinate2D(latitude: 30.3350, longitude: -122.0094), // Near Apple Park
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)  // San Francisco
            ]
            
            sampleLocations.forEach { coordinate in
                viewModel.storedLocations.append(
                    StoredLocation(
                        coordinate: coordinate,
                        timestamp: Date()
                    )
                )
            }
        }
}
