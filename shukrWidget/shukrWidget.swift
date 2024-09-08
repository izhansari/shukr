//
//  shukrWidget.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import WidgetKit
import SwiftUI
import AppIntents
import UIKit

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShukrEntry {
        ShukrEntry(date: Date(), tasbeeh: 1, configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> ShukrEntry {
        ShukrEntry(date: Date(), tasbeeh: 1, configuration: configuration)
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<ShukrEntry> {
        var entries: [ShukrEntry] = []
        
        let userDefaults = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget")
        let currentNumber = userDefaults?.integer(forKey: "count") ?? 0

        // Generate a timeline consisting of 7 entries a day apart, starting from the current date.
        let currentDate = Date()
        for dayOffset in 0 ..< 7 {
            let entryDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: currentDate)!
            let startOfDate =  Calendar.current.startOfDay(for: entryDate)
            let entry = ShukrEntry(date: startOfDate, tasbeeh: currentNumber, configuration: configuration)
            entries.append(entry)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct ShukrEntry: TimelineEntry {
    let date: Date
    let tasbeeh: Int
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
                Button(intent: AddIntent()){
                    Image(systemName: "plus").bold().font(.title2)
                        .frame(width: 40, height: 80)
                }
                
//                Button(intent: SubtractIntent()){
//                    Image(systemName: "minus").bold().font(.title2)
//                        .frame(width: 60, height: 30)
//                }
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
        .description("practice shukr with a tasbeeh easy reach to dedicate time")
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
    ShukrEntry(date: .now, tasbeeh: 10, configuration: .smiley)
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

    func perform() async throws -> some IntentResult {
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            var count = store.integer(forKey: "count")
            count = max(count - 1, 0)
            store.setValue(count, forKey: "count")
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }
        return .result()
    }
}
