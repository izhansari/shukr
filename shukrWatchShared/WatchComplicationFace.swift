//
//  WatchComplicationFace.swift
//  shukrWatchShared (watch widgets, and the iPhone app)
//
//  The watch-face complication's entry and view, moved out of WatchComplications.swift so the iPhone's Explore shukr
//  draws the real complication (owner, 2026-10-13: "make the watch ones real too"). The corner size is watchOS only;
//  outside a widget (`WatchRingFace.drawsStatically`) the timer gauges are drawn at the entry's moment instead.
//

import WidgetKit
import SwiftUI

struct PrayerComplicationEntry: TimelineEntry {
    let date: Date
    let prayer: WatchPrayer?
    let current: Bool

    /// The score colour for this entry's moment (grade changes get their own entries).
    var tint: Color {
        guard let p = prayer, current else { return .green }
        return WatchScoring.color(start: p.start, end: p.end, at: date)
    }
}

struct PrayerComplicationView: View {
    let entry: PrayerComplicationEntry
    @Environment(\.widgetFamily) private var widgetFamily
    /// The iPhone's Explore picks the size (outside a widget the environment's family is never right).
    var familyOverride: WidgetFamily? = nil
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    private var live: Bool {
        guard let p = entry.prayer else { return false }
        return entry.current && p.end > p.start
    }

    var body: some View {
        if let p = entry.prayer {
            switch family {
            case .accessoryCircular: circular(p)
            #if os(watchOS)
            case .accessoryCorner: corner(p)
            #endif
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
                if WatchRingFace.drawsStatically {
                    // iOS draws a circular ProgressView as a spinner: the gauge's ring drawn as it looks on the watch.
                    ZStack {
                        Circle().stroke(entry.tint.opacity(0.3), lineWidth: 4)
                        Circle().trim(from: 0, to: fraction(p))
                            .stroke(entry.tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        circleLabel(p)
                    }
                    .padding(3)
                } else {
                    ProgressView(timerInterval: p.start...p.end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: { circleLabel(p) }
                    .progressViewStyle(.circular)
                    .tint(entry.tint)
                    .widgetAccentable()   // the content, not the background
                }
            } else {
                // Not started: the phone's "next" look — a thin dashed ring, a tiny NEXT, dimmed name.
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .opacity(0.6)
                    .padding(2)
                    .widgetAccentable()
                VStack(spacing: 0) {
                    Text("NEXT").font(.system(size: 6, weight: .medium, design: .rounded)).tracking(1).opacity(0.7)
                    Image(systemName: WatchPrayers.symbol(p.name)).font(.system(size: 10, weight: .medium))
                    Text(p.name).font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    // No time line: four lines didn't fit a 41 mm circular slot.
                }
                .opacity(0.8)
                .widgetAccentable()
            }
        }
    }

    #if os(watchOS)
    @ViewBuilder private func corner(_ p: WatchPrayer) -> some View {
        Image(systemName: WatchPrayers.symbol(p.name))
            .font(.system(size: 20, weight: .medium))
            .widgetAccentable()
            .widgetLabel {
                if live {
                    ProgressView(timerInterval: p.start...p.end, countsDown: false) {
                        Text(p.name)
                    } currentValueLabel: {
                        Text(p.end, style: .time)
                    }
                    .tint(entry.tint)
                } else {
                    Text("\(p.name) \(Self.clock.string(from: p.start))")
                }
            }
    }
    #endif

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
                Group {
                    if WatchRingFace.drawsStatically {
                        ProgressView(value: fraction(p))
                    } else {
                        ProgressView(timerInterval: p.start...p.end, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                    }
                }
                .progressViewStyle(.linear)
                .tint(entry.tint)
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

    private func circleLabel(_ p: WatchPrayer) -> some View {
        VStack(spacing: 0) {
            Image(systemName: WatchPrayers.symbol(p.name)).font(.system(size: 11, weight: .medium))
            Text(p.name).font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    /// How far through the window it is at the entry's moment (the drawn-statically gauges).
    private func fraction(_ p: WatchPrayer) -> Double {
        p.end > p.start ? min(max(entry.date.timeIntervalSince(p.start) / p.end.timeIntervalSince(p.start), 0), 1) : 1
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()
}
