//
//  shukrWidget.swift
//  shukrWidget
//
//  Created by me on 8/3/24.
//

import WidgetKit
import SwiftUI
import AppIntents
import UIKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShukrEntry {
        ShukrEntry(date: Date(), tasbeeh: 1, isPaused: false, configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> ShukrEntry {
        ShukrEntry(date: Date(), tasbeeh: 1, isPaused: false, configuration: configuration)
    }
        
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<ShukrEntry> {
        var entries: [ShukrEntry] = []
        
        let userDefaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let currentNumber = userDefaults?.integer(forKey: "count") ?? 0
        let isPaused = userDefaults?.bool(forKey: "paused") ?? false // Get isPaused value from UserDefaults

        // Generate a timeline consisting of 7 entries a day apart, starting from the current date.
        let currentDate = Date()
        for dayOffset in 0 ..< 7 {
            let entryDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDate)!
            let startOfDate =  Calendar.current.startOfDay(for: entryDate)
            let entry = ShukrEntry(date: startOfDate, tasbeeh: currentNumber, isPaused: isPaused, configuration: configuration) // Pass isPaused
            entries.append(entry)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

}

struct ShukrEntry: TimelineEntry {
    let date: Date
    let tasbeeh: Int
    let isPaused: Bool // Add isPaused state
    let configuration: ConfigurationAppIntent
}


struct ShukrEntryView : View {
    var entry: ShukrEntry

    var body: some View {
        HStack {
            ZStack{
                Circle()
                    .stroke(lineWidth: 24)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
                Circle()
                    .stroke(lineWidth: 0.34)
                    .frame(width: 76, height: 76)
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.3), lineWidth: 2)
                            .blur(radius: 5)
                            .mask {
                                Circle()
                                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                    }
                Circle()
                    .trim(from: 0, to: CGFloat(entry.tasbeeh) / 100)
                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("\(entry.tasbeeh)").bold().font(.title)
            }
            
            Spacer()
            
            VStack {
                if entry.isPaused {
                    // Show play button
                    Button(intent: ResumeIntent()) {
                        Image(systemName: "play.fill").bold().font(.title2)
                            .frame(width: 40, height: 80)
                    }
                } else {
                    // Show plus button
                    Button(intent: AddIntent()) {
                        Image(systemName: "plus").bold().font(.title2)
                            .frame(width: 40, height: 80)
                    }
                }
            }

        }
        .padding(.horizontal)
        .padding(.horizontal)
    }

}

struct shukrWidget: Widget {
    let kind: String = "shukrWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            ShukrEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Timer & Counter")
        .description("practice shukr with an easy to reach tasbeeh")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }
    
    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

#Preview(as: .systemMedium) {
    shukrWidget()
} timeline: {
    ShukrEntry(date: .now, tasbeeh: 10, isPaused: false, configuration: .smiley)
}


/// custom extension so we dont have to write this out everytime.
extension Date{
    var weekdayDisplayFormat: String{
        self.formatted(.dateTime.weekday(.wide))
    }
    
    var dayDisplayFormat: String{
        self.formatted(.dateTime.day())
    }
}


struct AddIntent: AppIntent {
    static var title: LocalizedStringResource = "add"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            var count = store.integer(forKey: "count")
            count = min(count + 1, 10000)
            store.setValue(count, forKey: "count")
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        return .result()
    }
}

struct SubtractIntent: AppIntent {
    static var title: LocalizedStringResource = "Subtract"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
//        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
//            var count = store.integer(forKey: "count")
//            count = max(count - 1, 0)
//            store.setValue(count, forKey: "count")
//            WidgetCenter.shared.reloadAllTimelines()
//            return .result()
//        }
        return .result()
    }
}

struct ResumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
//        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
//            store.setValue(false, forKey: "paused")
//            WidgetCenter.shared.reloadAllTimelines()
//            return .result()
//        }
        return .result()
    }
}





// MARK: - perplexity compass widget

import WidgetKit
import SwiftUI
import CoreLocation

struct CompassWidget: Widget {
    let kind: String = "CompassWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompassTimelineProvider()) { entry in
            CompassWidgetView(entry: entry)
                .containerBackground(Color.white, for: .widget)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Compass")
        .description("Shows current heading or location")
        .supportedFamilies([.systemSmall])
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var heading: Double = 0
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingHeading()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.magneticHeading
        WidgetCenter.shared.reloadTimelines(ofKind: "CompassWidget")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            WidgetCenter.shared.reloadTimelines(ofKind: "CompassWidget")
        }
    }
}

struct CompassEntry: TimelineEntry {
    let date: Date
    let heading: Double
    let latitude: Double
    let longitude: Double
    let showLocation: Bool
}

struct CompassTimelineProvider: TimelineProvider {
    let locationManager = LocationManager()
    
    func placeholder(in context: Context) -> CompassEntry {
        CompassEntry(date: Date(), heading: 0, latitude: 0, longitude: 0, showLocation: false)
    }
    
    func getSnapshot(in context: Context, completion: @escaping (CompassEntry) -> Void) {
        let defaults = UserDefaults(suiteName: "group.myAppGroupID")!
        let showLocation = defaults.bool(forKey: "showLocation")

        let entry = CompassEntry(date: Date(), heading: locationManager.heading,
                                 latitude: locationManager.latitude, longitude: locationManager.longitude,
                                 showLocation: showLocation)
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<CompassEntry>) -> Void) {
        let defaults = UserDefaults(suiteName: "group.myAppGroupID")!
        let showLocation = defaults.bool(forKey: "showLocation")

        let currentDate = Date()
        let entry = CompassEntry(date: currentDate, heading: locationManager.heading,
                                 latitude: locationManager.latitude, longitude: locationManager.longitude,
                                 showLocation: showLocation)
        let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(60)))
        completion(timeline)
    }
}


struct ToggleLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Show Location"
    
    // If you need parameters, define them here.
    // For a simple toggle, we typically don’t need any parameters.

    func perform() async throws -> some IntentResult {
        // Read the existing state (true/false) from UserDefaults (using an App Group).
        let defaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let currentValue = defaults.bool(forKey: "showLocation")
        
        // Flip it
        let newValue = !currentValue
        defaults.set(newValue, forKey: "showLocation")
        
        // Ask the system to reload your widget so it reflects this updated state.
        WidgetCenter.shared.reloadTimelines(ofKind: "CompassWidget")
        
        // Return a successful result (no view changes needed here).
        return .result()
    }
}


struct ResumeIntent2: AppIntent {
    static var title: LocalizedStringResource = "Resume"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            store.setValue(false, forKey: "paused")
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        return .result()
    }
}


struct CompassWidgetView: View {
    var entry: CompassEntry
//    @State private var showLocation: Bool = false
    

    var body: some View {
        ZStack {
            // Main content centered
            VStack {
                if entry.showLocation {
                    VStack {
                        Text("Lat: \(entry.latitude, specifier: "%.4f")")
                        Text("Long: \(entry.longitude, specifier: "%.4f")")
                        Text("Head: \(entry.heading, specifier: "%.2f")")
                    }
                    .font(.caption)
                } else {
                    ZStack{
                        Circle()
                            .stroke(Color.gray, lineWidth: 2)
                            .padding()

                        ForEach(0..<360/30, id: \.self) { i in
                            Rectangle()
                                .fill(Color.gray)
                                .frame(width: 2, height: 10)
                                .offset(y: -40)
                                .rotationEffect(.degrees(Double(i) * 30))
                        }

                        Image(systemName: "location.north.fill")
                            .foregroundColor(.red)
                            .rotationEffect(.degrees(-entry.heading))

                        Text("\(Int(entry.heading))°")
                            .font(.caption)
                            .offset(y: 20)
                    }
                }
            }

            // Button positioned in the top-right corner
//            VStack {
//                HStack {
//                    Spacer() // Push the button to the right
//                    Button(action: {
//                        showLocation.toggle()
//                    }) {
//                        Image(systemName: showLocation ? "location" : "location.north.fill")
//                            .frame(width: 30, height: 30)
//                            .background(Color.white.opacity(0.8))
//                            .clipShape(Circle())
//                            .padding(10)
//                    }
//                }
//                Spacer() // Push the button up to the top
//            }
            
            
            // Top-right corner
            VStack {
                HStack {
                    Spacer()
                    Button(intent: ToggleLocationIntent()) { // <-- Use intent!
                        Image(systemName: entry.showLocation ? "location" : "location.north.fill")
                            .frame(width: 15, height: 15)
                            .background(Color.white.opacity(0.8))
                            .clipShape(Circle())
//                            .padding(10)
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


//struct CompassWidgetView: View {
//    var entry: CompassEntry
//    @State private var showLocation: Bool = false
//    
//    var body: some View {
//        ZStack {
//            if showLocation {
//                VStack {
//                    Text("Lat: \(entry.latitude, specifier: "%.4f")")
//                    Text("Long: \(entry.longitude, specifier: "%.4f")")
//                    Text("Head: \(entry.heading, specifier: "%.2f"))")
//                }
//                .font(.caption)
//            } else {
//                Circle()
//                    .stroke(Color.gray, lineWidth: 2)
//                    .padding()
//
//                
//                ForEach(0..<360/30, id: \.self) { i in
//                    Rectangle()
//                        .fill(Color.gray)
//                        .frame(width: 2, height: 10)
//                        .offset(y: -40)
//                        .rotationEffect(.degrees(Double(i) * 30))
//                }
//                
//                Image(systemName: "location.north.fill")
//                    .foregroundColor(.red)
//                    .rotationEffect(.degrees(-entry.heading))
//            
//                
//                Text("\(Int(entry.heading))°")
//                    .font(.caption)
//                    .offset(y: 20)
//            }
//            
//            // Top-right positioned button
//            ZStack(alignment: .topLeading){
//                Button(action: {
//                    showLocation.toggle()
//                }) {
//                    Image(systemName: showLocation ? "location" : "location.north.fill")
//                        .frame(width: 30, height: 30)
//                        .background(Color.white.opacity(0.8))
//                        .clipShape(Circle())
//                }
//            }
//            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure it takes up the full widget space
//
//
//            
//            // this button is clickable
////            Button(intent: ResumeIntent()) {
////                Image(systemName: "play.fill").bold().font(.title2)
////                    .frame(width: 40, height: 80)
////            }
////
//            // this button doesnt wanna be clickable ... :(
////            VStack {
////                HStack {
////                    Spacer()
////                    Button(action: {
////                        showLocation.toggle()
////                    }) {
////                        Image(systemName: showLocation ? "location" : "location.north.fill")
////                                .frame(width: 40, height: 80)
////                        
////                    }
////                }
////                Spacer()
////            }
//            
//            // even this doesnt work. plus its a bad way to do this cuz the button becomes the whole vstack lol.
////            Button(action: {
////                showLocation.toggle()
////            }) {
////                VStack {
////                    HStack {
////                        Spacer()
////                            Image(systemName: showLocation ? "location" : "location.north.fill")
////                                    .frame(width: 40, height: 80)
////                    }
////                    Spacer()
////                }
////            }
//
//
//            
//            
//        }
////        .border(.green)
//    }
//}

#Preview(as: .systemSmall) {
    CompassWidget()
} timeline: {
//    ShukrEntry(date: .now, tasbeeh: 10, isPaused: false, configuration: .smiley)
    CompassEntry(date: .now, heading: 10, latitude: 33, longitude: 43, showLocation: true)
}

//import WidgetKit
//import SwiftUI
//import CoreLocation
//
//struct CompassWidget: Widget {
//    let kind: String = "CompassWidget"
//    
//    var body: some WidgetConfiguration {
//        StaticConfiguration(kind: kind, provider: CompassTimelineProvider()) { entry in
//            CompassWidgetView(entry: entry)
//                .containerBackground(Color.yellow, for: .widget)
//        }
//        .configurationDisplayName("Compass")
//        .description("Shows current heading")
//        .supportedFamilies([.systemSmall])
//    }
//}
//
//struct CompassTimelineProvider: TimelineProvider {
//    let locationManager = LocationManager()
//    
//    func placeholder(in context: Context) -> CompassEntry {
//        CompassEntry(date: Date(), heading: 0)
//    }
//    
//    func getSnapshot(in context: Context, completion: @escaping (CompassEntry) -> Void) {
//        let entry = CompassEntry(date: Date(), heading: locationManager.heading)
//        completion(entry)
//    }
//    
//    func getTimeline(in context: Context, completion: @escaping (Timeline<CompassEntry>) -> Void) {
//        let currentDate = Date()
//        let entry = CompassEntry(date: currentDate, heading: locationManager.heading)
//        let timeline = Timeline(entries: [entry], policy: .after(currentDate.addingTimeInterval(60)))
//        completion(timeline)
//    }
//}
//
//struct CompassEntry: TimelineEntry {
//    let date: Date
//    let heading: Double
//}
//
//struct CompassWidgetView: View {
//    var entry: CompassEntry
//    
//    var body: some View {
//        ZStack {
//            Circle()
//                .stroke(Color.gray, lineWidth: 2)
//            
//            ForEach(0..<360/30, id: \.self) { i in
//                Rectangle()
//                    .fill(Color.gray)
//                    .frame(width: 2, height: 10)
//                    .offset(y: -40)
//                    .rotationEffect(.degrees(Double(i) * 30))
//            }
//            
//            Image(systemName: "location.north.fill")
//                .foregroundColor(.red)
//                .rotationEffect(.degrees(-entry.heading))
//            
//            Text("\(Int(entry.heading))°")
//                .font(.caption)
//                .offset(y: 20)
//        }
//        .padding()
//    }
//}
//
//class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
//    private let locationManager = CLLocationManager()
//    @Published var heading: Double = 0
//    
//    override init() {
//        super.init()
//        locationManager.delegate = self
//        locationManager.startUpdatingHeading()
//    }
//    
//    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
//        heading = newHeading.magneticHeading
//        WidgetCenter.shared.reloadTimelines(ofKind: "CompassWidget")
//    }
//}
