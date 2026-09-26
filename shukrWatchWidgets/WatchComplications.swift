//
//  WatchComplications.swift
//  shukr Watch complications
//
//  The prayer on your watch face (any face that takes complications). Same prayer as the phone's
//  widget: the one that's on (not yet prayed), else the next; after Isha, tomorrow's Fajr.
//  - Circular: the time left drains round the ring live, symbol and name inside.
//  - Corner: the symbol, with the ring as a curved gauge and the time along the edge.
//  - Rectangular: name, "ends 6:48 PM" / "at 5:32 AM", a live bar or countdown.
//  - Inline: "Asr · ends 6:48 PM".
//  One entry per prayer start / end; the rings and countdowns move on their own in between.
//

import WidgetKit
import SwiftUI

@main
struct ShukrWatchWidgets: WidgetBundle {
    var body: some Widget {
        PrayerComplication()
    }
}

struct PrayerComplicationEntry: TimelineEntry {
    let date: Date
    let prayer: WatchPrayer?
    let current: Bool
}

struct PrayerComplicationProvider: TimelineProvider {
    private func entry(at date: Date) -> PrayerComplicationEntry {
        let r = WatchPrayers.relevant(at: date)
        return PrayerComplicationEntry(date: date, prayer: r?.prayer, current: r?.current ?? false)
    }

    func placeholder(in context: Context) -> PrayerComplicationEntry {
        let now = Date()
        return PrayerComplicationEntry(date: now, prayer: WatchPrayer(name: "Asr", start: now.addingTimeInterval(-1800),
                                                                       end: now.addingTimeInterval(5400)), current: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerComplicationEntry) -> Void) {
        let e = entry(at: Date())
        completion(e.prayer == nil ? placeholder(in: context) : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerComplicationEntry>) -> Void) {
        let now = Date()
        let dates = [now] + WatchPrayers.boundaries(after: now).prefix(12)
        let entries = dates.map { entry(at: $0.addingTimeInterval($0 == now ? 0 : 1)) }
        let refresh = dates.last.map { $0.addingTimeInterval(60) } ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct PrayerComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShukrWatchPrayer", provider: PrayerComplicationProvider()) { entry in
            PrayerComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Prayer")
        .description("The prayer that's on, and how long it has left.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct PrayerComplicationView: View {
    let entry: PrayerComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var live: Bool {
        guard let p = entry.prayer else { return false }
        return entry.current && p.end > p.start
    }

    var body: some View {
        if let p = entry.prayer {
            switch family {
            case .accessoryCircular: circular(p)
            case .accessoryCorner: corner(p)
            case .accessoryRectangular: rectangular(p)
            default: inline(p)
            }
        } else {
            Image(systemName: "moon.stars")   // no location yet: open shukr on the phone
        }
    }

    private func circular(_ p: WatchPrayer) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            if live {
                ProgressView(timerInterval: p.start...p.end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    VStack(spacing: 0) {
                        Image(systemName: WatchPrayers.symbol(p.name)).font(.system(size: 11, weight: .medium))
                        Text(p.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .progressViewStyle(.circular)
                .tint(.green)
            } else {
                VStack(spacing: 0) {
                    Image(systemName: WatchPrayers.symbol(p.name)).font(.system(size: 11, weight: .medium))
                    Text(p.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(Self.clock.string(from: p.start))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
        }
        .widgetAccentable()
    }

    @ViewBuilder private func corner(_ p: WatchPrayer) -> some View {
        Image(systemName: WatchPrayers.symbol(p.name))
            .font(.system(size: 20, weight: .medium))
            .widgetAccentable()
            .widgetLabel {
                if live {
                    ProgressView(timerInterval: p.start...p.end, countsDown: true) {
                        Text(p.name)
                    } currentValueLabel: {
                        Text(p.end, style: .time)
                    }
                    .tint(.green)
                } else {
                    Text("\(p.name) \(Self.clock.string(from: p.start))")
                }
            }
    }

    private func rectangular(_ p: WatchPrayer) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: WatchPrayers.symbol(p.name))
                Text(p.name).font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .widgetAccentable()
            (Text(live ? "ends " : "at ") + Text(live ? p.end : p.start, style: .time))
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.secondary)
            if live {
                ProgressView(timerInterval: p.start...p.end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(.green)
            } else {
                (Text("in ") + Text(p.start, style: .relative))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func inline(_ p: WatchPrayer) -> some View {
        Label {
            Text(p.name + (live ? " · ends " : " · ")) + Text(live ? p.end : p.start, style: .time)
        } icon: {
            Image(systemName: WatchPrayers.symbol(p.name))
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()
}
