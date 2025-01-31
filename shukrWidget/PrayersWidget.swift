//
//  CompassWidget.swift
//  shukr
//
//  Created on 1/22/25.
//


// MARK: - perplexity compass widget

import WidgetKit
import SwiftUI
import CoreLocation
import Adhan
import AppIntents
import Combine


struct PrayersWidget: Widget {
    let kind: String = "PrayersWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, provider: PrayersWidgetTimelineProvider()) { entry in
            PrayersWidgetView(entry: entry)
                .containerBackground(Color("widgetBgColor"), for: .widget)
//                .containerBackground(Color("bgColor")/*Color.white*/, for: .widget)
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Prayers")
        .description("See todays prayers & how much time is left")
        .supportedFamilies([.systemSmall])
    }
}

//moved PrayersWidgetLocationManager to locMan file

struct PrayersWidgetEntry: TimelineEntry {
    let date: Date
    let heading: Double
    let latitude: Double
    let longitude: Double
    let toggleShowAllTImes: Bool
    let prayerDict: [String: (start: Date, end: Date, window: TimeInterval)]
    let todayPrayerTimes: PrayerTimes
    let locationName: String // New property
    let textToggle: Bool
}


import WidgetKit
import SwiftUI
import CoreLocation
import Adhan

struct PrayersWidgetTimelineProvider: AppIntentTimelineProvider {
    let locationManager = PrayersWidgetLocationManager()

    func placeholder(in context: Context) -> PrayersWidgetEntry {
        // Provide a placeholder with *dummy* prayer times so SwiftUI can render a preview
        let dummyCoordinates = Coordinates(latitude: 0, longitude: 0)
        let dummyParams = CalculationMethod.northAmerica.params
        let dummyDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        
        // Safe to force-unwrap for placeholder if you want
        let dummyTimes = PrayerTimes(coordinates: dummyCoordinates,
                                     date: dummyDateComponents,
                                     calculationParameters: dummyParams)!
        let dummyWindow = PrayerUtils.createDummyWindows()
        let dummyLocation = "Dummy Location"
        
        return PrayersWidgetEntry(
            date: Date(),
            heading: 0,
            latitude: 0,
            longitude: 0,
            toggleShowAllTImes: false, prayerDict: dummyWindow,
            todayPrayerTimes: dummyTimes, locationName: dummyLocation, textToggle: false
        )
    }
    
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> PrayersWidgetEntry {
        // Called when the system wants a quick "snapshot" — often for widget previews.
        // You can replicate the logic from 'timeline' or do something simpler.
        return await makeEntry()
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<PrayersWidgetEntry> {
        let entry = await makeEntry()
        // Refresh policy: e.g. every 60 seconds
        let nextRefresh = Date().addingTimeInterval(60)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        return timeline
    }
    
    /// Helper function that calculates the data you want in the widget entry.
    private func makeEntry() async -> PrayersWidgetEntry {
        // Grab the values from your location manager
        let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")!
        let showLocation = store.bool(forKey: "toggleShowAllTImes")
        let latitude = store.double(forKey: "lastLatitude")
        let longitude = store.double(forKey: "lastLongitude")
        let locationName = store.string(forKey: "lastCityName") ?? "Wonderland"
        let textToggle = store.bool(forKey: "widgetTextToggle")
//        let latitude = locationManager.latitude
//        let longitude = locationManager.longitude
//        let locationName = locationManager.locationName // Fetch updated location name
        let heading = locationManager.heading

        // Attempt to get real prayer times from your utility
        // Fallback if there's an error (e.g. location not yet available).
        var prayerTimes: PrayerTimes
        let coordinates = Coordinates(latitude: latitude, longitude: longitude)
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        var windows = PrayerUtils.createDummyWindows()
        do {
            let params = PrayerUtils.getCalculationParameters()
            prayerTimes = try PrayerUtils.getPrayerTimes(for: Date(), coordinates: coordinates, params: params)
            windows = PrayerUtils.createWindowsFromTimes(prayerTimes)
        } catch {
            // If there's an error, either throw or use a fallback
            // For example, you could use dummy times or just return some default
            let fallbackCalcParams = CalculationMethod.northAmerica.params
            print("ran catch block fallback for PrayerUtils")
            prayerTimes = PrayerTimes(
                coordinates: coordinates,
                date: dateComponents,
                calculationParameters: fallbackCalcParams
            )!
        }
        
        // Finally, create our entry
        let entry = PrayersWidgetEntry(
            date: Date(),
            heading: heading,
            latitude: latitude,
            longitude: longitude,
            toggleShowAllTImes: showLocation, prayerDict: windows,
            todayPrayerTimes: prayerTimes, locationName: locationName, textToggle: textToggle
        )
        
        return entry
    }
}



struct PrayersWidgetView: View {
    @ObservedObject var locationManager = PrayersWidgetLocationManager()
    var entry: PrayersWidgetEntry
    let prayerOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        
    var body: some View {
        ZStack {
            // Main content centered
            if entry.toggleShowAllTImes {
//                ZStack {
////                    Color.black
//                    Color("widgetBgColor")
//                        .ignoresSafeArea()
//                }
                //Old Top Button
                VStack{
                    HStack{
    
                        Button(intent: showListToggleIntent()) {
                            Image(systemName: "chevron.left")
                                .font(.caption2)
                                .foregroundColor(.primary/*.white*/)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        
                    }
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 13)
                
                VStack (alignment: .center){
                    
                    //debugDetailsView(entry: entry)
                    
                    Label(entry.locationName, systemImage: "location.fill")
                        .fontDesign(.rounded)
                        .font(.system(size: 12))

                    Divider().background(Color.secondary)
                    
                    TimesListView(prayerOrder: prayerOrder, entry: entry)
                }
                .foregroundColor(.primary/*.white*/)
            }
            else {
                WidgetPrayerCircleView(entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    struct TimesListView: View {
        let prayerOrder: [String]
        let entry: PrayersWidgetEntry
        
        var body: some View {
            VStack(spacing: 3){
                ForEach(prayerOrder, id: \.self) { name in
                    if let prayer = entry.prayerDict[name] {
                        let currentPrayer: Bool = prayer.start <= Date() && Date() < prayer.end
                        var progressColor: Color {
                            guard (currentPrayer) else { return .secondary }
                            
                            let elapsedDuration = Date().timeIntervalSince(prayer.start)
                            let totalDuration = prayer.end.timeIntervalSince(prayer.start)
                            let progress: Double = elapsedDuration / totalDuration
                            
                            if progress < 0.5 { return .green }
                            else if progress < 0.75 { return .yellow }
                            else if progress < 1 { return .red }
                            else {return .secondary}
                        }
                        HStack {
                            Text(name)
                            Spacer()
                            Text("\(shortTime(prayer.start))")
                        }
                        .padding(.horizontal)
                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
                        .fontWeight(currentPrayer ? .regular : .thin)
//                        .foregroundStyle(.white)
                        .foregroundStyle(/*currentPrayer ? progressColor : */.primary/*.white*/)
                        .font(.system(size: 13))
//                        .border(prayer.start <= Date() && Date() < prayer.end ? .green : .clear, width: 0.5)
                        if name != "Isha"{
                            Divider().background(Color.secondary.opacity(0.4))
                        }
                        
                        
                    } else {
                        HStack{
                            Text(name)
                            Spacer()
                            Text("7:00")
                        }
                        
                    }
                }
            }
            .font(.footnote)
            .frame(width: 120)
        }
    }

    
    struct WidgetPrayerCircleView: View {
        let entry: PrayersWidgetEntry
        
        let prayerOrder = ["Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha"]
        

        var relevantPrayer: (name: String, current: Bool, start: Date, end: Date, window: TimeInterval) {
            let now = Date()
            
            /// Check if indexed prayer is a current prayer -- else check if indexed prayer is the next one
            for name in prayerOrder {
                if let prayer = entry.prayerDict[name] {
                    //if prayer.start <= now  && now < prayer.end && name != "Sunrise" { // current prayer
                    if prayer.start <= now  && now < prayer.end { // current prayer

                        return (name, true, prayer.start, prayer.end, prayer.window)
                    }
                    else if now < prayer.start { // next prayer
                        return (name, false, prayer.start, prayer.end, prayer.window)
                    }
                }
            }
            
            /// If we've gone through all prayers and none are current or next up then it means we've passed the last prayer of the day.
            /// So lets display tomorrow's first prayer.
            return ("Fajr", false, Date(), Date(), 400)
            
        }
                
        var progress: Double {
            let now = Date()
            let startDate = relevantPrayer.start
            let endDate = relevantPrayer.end
            
            // Ensure `now` is within the range of startDate and endDate
            guard now >= startDate && now <= endDate else {
                return now < startDate ? 0.0 : 1.0
            }
            let totalDuration = endDate.timeIntervalSince(startDate)
            let elapsedDuration = now.timeIntervalSince(startDate)

            return elapsedDuration / totalDuration
        }
        
        private var progressColor: Color {
            if progress < 0.5 { return .green }
            else if progress < 0.75 { return .yellow }
            else if progress < 1 { return .red }
            else {return .gray}
        }

        private var timeStyle: Text.DateStyle {
            if entry.textToggle { return .relative }
            else { return .time }
        }

        
        var body: some View {
            ZStack {
//                Color.black
//                    .ignoresSafeArea()
                
                VStack{
                    Spacer()
                    
                    // Circular Timer with Text Button
                    Button(intent: textToggleIntent()){
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                            
                            Circle()
                                .trim(from: 0, to: progress) // Adjust progress value (0 to 1)
                                .stroke(
                                    progressColor,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .butt)
                                )
                                .rotationEffect(.degrees(-90))
                            
                            VStack(spacing: 4) {
                                HStack(alignment: .center, spacing: 4){
                                    Image(systemName: prayerIcon(for: relevantPrayer.name))
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary/*.white*/)
                                    Text(relevantPrayer.name)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.primary/*.white*/)
                                }
                                Text(relevantPrayer.current ? relevantPrayer.end : relevantPrayer.start, style: timeStyle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary/*.white*/.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(width: 90, height: 90) // Scaled for widget size
                        
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    Spacer()
                }
                VStack(spacing: 0) {
                    Spacer()
                    // Bottom Button Row
                    HStack(spacing: 0) {
                        BottomRowButtonStyle(intent: OpenCompassIntent(), systemImage: "location")
                        Divider().background(Color.gray)
                        BottomRowButtonStyle(intent: OpenTasbeehIntent(), systemImage: "circle.hexagonpath")
                        Divider().background(Color.gray)
                        BottomRowButtonStyle(intent: showListToggleIntent(), systemImage: "list.bullet")
                        
                    }
                    .frame(height: 23)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.gray, lineWidth: 0.75) // Border
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
                
                VStack{
                    HStack{
                        Button(intent: MarkCompleteIntent()) {
                            Image(systemName: "circle")//"checkmark.circle")
                                .font(.system(size: 15)) // Adjust font size as needed
                                .frame(width: 15, height: 15)
                                .foregroundColor(.primary/*.white*/)
                        }
                        .padding(.all, 14)
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        
    }
    
    struct BottomRowButtonStyle: View {
        let intent: any AppIntent
        let systemImage: String
        
        var body: some View {
            Button(intent: intent) {
                Image(systemName: systemImage)
                    .font(.system(size: 12)) // Adjust font size as needed
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.primary/*.white*/)
            }
            .buttonStyle(.plain)
        }
        
    }
    
    struct debugDetailsView: View {
        let entry: PrayersWidgetEntry
        var body: some View {
            HStack{
                Text("meth:")
                Text("\(entry.todayPrayerTimes.calculationParameters.method)")
            }
            HStack{
                Text("mad:")
                Text("\(entry.todayPrayerTimes.calculationParameters.madhab)")
            }
            Text("Lat: \(entry.latitude, specifier: "%.4f")")
            Text("Long: \(entry.longitude, specifier: "%.4f")")
        }
    }
    
}





#if DEBUG
import SwiftUI
import WidgetKit
import Adhan

#Preview(as: .systemSmall) {
    PrayersWidget()
} timeline: {
    // 1. Create some dummy coordinates and parameters
    let dummyCoordinates = Coordinates(latitude: 40.7128, longitude: -74.0060)
    let dummyDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let dummyParams = CalculationMethod.northAmerica.params
    let dummyWindows = PrayerUtils.createDummyWindows()
    let dummyLocationName = "dummy location"

    // 2. Force-unwrap a dummy PrayerTimes. Safe enough for preview purposes.
    let dummyPrayerTimes = PrayerTimes(
        coordinates: dummyCoordinates,
        date: dummyDateComponents,
        calculationParameters: dummyParams
    )!

    // 3. Pass that to your custom widget entry
    PrayersWidgetEntry(
        date: .now,
        heading: 10,
        latitude: 33,
        longitude: 43,
        toggleShowAllTImes: true, prayerDict: dummyWindows,
        todayPrayerTimes: dummyPrayerTimes, locationName: dummyLocationName, textToggle: false
    )
}
#endif


//struct WidgetPrayerCircleView: View {
//
//    var body: some View {
//        ZStack {
//            Color.black
//                .ignoresSafeArea()
//
//            VStack{
//                Spacer()
//
//                // Circular Timer with Text Button
//                Button(action: {
//                    // Add action here
//                }) {
//                    ZStack {
//                        Circle()
//                            .stroke(Color.gray.opacity(0.2), lineWidth: 6)
//
//                        Circle()
//                            .trim(from: 0, to: 0.75) // Adjust progress value (0 to 1)
//                            .stroke(
//                                AngularGradient(
//                                    gradient: Gradient(colors: [Color.green, Color.gray]),
//                                    center: .center
//                                )
//                                ,
//                                style: StrokeStyle(lineWidth: 2, lineCap: .butt)
//                            )
//                            .rotationEffect(.degrees(-90))
//
//                        VStack(spacing: 4) {
//                            HStack(alignment: .center, spacing: 0){
//                                Image(systemName: "sun.and.horizon.fill")
//                                    .font(.system(size: 15))
//                                    .foregroundColor(.white)
//                                Text("Asr")
//                                    .font(.system(size: 12, weight: .bold))
//                                    .foregroundColor(.white)
//                            }
//                            Text("3h 22m left")
//                                .font(.system(size: 10))
//                                .foregroundColor(.white.opacity(0.7))
//                        }
//                    }
//                    .frame(width: 90, height: 90) // Scaled for widget size
//
//                }
//                .buttonStyle(.plain)
//                .padding(.top, 3)
//
//                Spacer()
//                Spacer()
//            }
//            VStack(spacing: 0) {
//                Spacer()
//                // Bottom Button Row
//                HStack(spacing: 0) {
//                    BottomRowButtonStyle(action: {}, systemImage: "location.fill")
//                    Divider().background(Color.gray)
//                    BottomRowButtonStyle(action: {}, systemImage: "checkmark")
//                    Divider().background(Color.gray)
//                    BottomRowButtonStyle(action: {}, systemImage: "list.bullet")
//
//                }
//                .frame(height: 20)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 7)
//                        .stroke(Color.gray, lineWidth: 0.75) // Border
//                )
//                .clipShape(RoundedRectangle(cornerRadius: 7))
//                .padding(.horizontal)
//                .padding(.bottom, 10)
//            }
//        }
//    }
//
//    struct BottomRowButtonStyle: View {
//        let action: () -> Void
//        let systemImage: String
//        var body: some View {
//            Button(action: {
//                action()
//            }) {
//                Image(systemName: systemImage)
//                    .font(.system(size: 10))
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .foregroundColor(.white)
//            }
//            .buttonStyle(.plain)
//        }
//    }
//
//
//}



//struct WidgetRingStyle: View {
//    let prayerName: String
//    @Environment(\.colorScheme) var colorScheme // Access the environment color scheme
//
//    private var progress: Double {
//        0.3
//    }
//    private var progressColor: Color {
//        if progress > 0.5 { return .green }
//        else if progress > 0.25 { return .yellow }
//        else if progress > 0 { return .red }
//        else {return .gray}
//    }
//    private var clockwiseProgress: Double {
//        1 - progress
//    }
//    private var pulseRate: Double {
//        if progress > 0.5 { return 3 }
//        else if progress > 0.25 { return 2 }
//        else { return 1 }
//    }
//    private var frameSize: CGFloat { 120 }
//    private var outerRingSize: CGFloat { 14 }
//    private var innerRingSize: CGFloat { 6 }
//    private var offset: CGFloat { 1 }
//    private var dummyTimeLeft: TimeInterval{ 10403 } //this should be calculated from now to prayer's endTime using endTime.timeIntervalSinceNow
//
//    private func iconName(for prayerName: String) -> String {
//        switch prayerName.lowercased() {
//        case "fajr":
//            return "sunrise.fill"
//        case "dhuhr":
//            return "sun.max.fill"
//        case "asr":
//            return "sun.haze.fill"
//        case "maghrib":
//            return "sunset.fill"
//        default:
//            return "moon.stars.fill"
//        }
//    }
//    
//    func timeLeftString(from timeInterval: TimeInterval) -> String {
//        let totalSeconds = Int(timeInterval)
//        let hours = totalSeconds / 3600
//        let minutes = (totalSeconds % 3600) / 60
//        let seconds = totalSeconds % 60
//
//        // Building the formatted string
//        var components: [String] = []
//        if hours > 0 { components.append("\(hours)h") }
//        if minutes > 0 { components.append("\(minutes)m") }
//        if totalSeconds < 60 { components.append("\(seconds)s") } // Only show seconds if less than a minute
//        if components.isEmpty { return "0s left" } // If no time left, return "0s left"
//        return components.joined(separator: " ") + " left"
//    }
//
//
//    
//    var body: some View {
//        ZStack {
//            
//            // inner content
//            VStack(spacing: 5){
//                HStack (spacing: 2){
//                    Image(systemName: iconName(for: prayerName))
//                        .foregroundColor(.secondary)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                        .font(.callout)
//                    Text(prayerName)
//                        .fontDesign(.rounded)
//                        .fontWeight(.thin)
//                        .foregroundStyle(.secondary)
//                        .font(.callout)
//                }
////                    Text(timeLeftString(from: dummyTimeLeft)) // replace with real prayer
////                        .font(.system(size: 12))
////                        .fontDesign(.rounded)
////                        .fontWeight(.thin)
////                        .foregroundStyle(.secondary)
//            }
//            
//            // Outer Circle with Dynamic Shadow
//            Circle()
//                .stroke(lineWidth: outerRingSize)
//                .frame(width: frameSize, height: frameSize)
//                .foregroundColor(Color("NeuRing"))
//                .shadow(
//                    color: Color("NeuDarkShad"), // shadow top lighter
//                    radius: 4,
//                    x: 2,
//                    y: 2
//                )
//                .shadow(
//                    color: Color("NeuLightShad"), // shadow top lighter
//                    radius: 6,
//                    x: -2,
//                    y: -2
//                )
//            
//            
//            // progress ring
//            Circle()
//                .trim(from: 0, to: clockwiseProgress)
//                .stroke(style: StrokeStyle(
//                    lineWidth: innerRingSize,
//                    lineCap: .round
//                ))
//                .fill(
//                    Color("bgColor")
//                    //indent shadow
//                        .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 0.5, x: -1, y: 1))
//
//                )
//            //outdented shadow
//                .shadow(color: Color("NeuDarkShad").opacity(0.5), radius: 0.5, x: -1, y: 1)
//
//                .frame(width: frameSize, height: frameSize)
//                .rotationEffect(.degrees(-90))
//            
//            // Ring tip with shadow
//            Circle()
//                .trim(from: clockwiseProgress - 0.001,
//                      to:   clockwiseProgress)
//                .stroke(style: StrokeStyle(
//                    lineWidth: innerRingSize,
//                    lineCap: .round
//                ))
//                .frame(width: frameSize, height: frameSize)
//                .rotationEffect(.degrees(-90))
//                .foregroundStyle(progressColor)
//            
//
//        }
//    }
//}


