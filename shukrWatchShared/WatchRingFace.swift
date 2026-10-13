//
//  WatchRingFace.swift
//  shukrWatchShared (watch app, watch widgets, and the iPhone app)
//
//  The watch's prayer ring as it looks — the soft band, the dashes of a prayer to come, the score arc, the name and its
//  time — with no taps or haptics (those stay in WatchPrayerRing, ShukrWatchApp.swift). Shared so the iPhone's Explore
//  shukr draws the watch's real ring (owner, 2026-10-13: "make the watch ones real too").
//

import SwiftUI

/// The phone's public soft look on the watch (CircleTheme.publicLook, palette greyBlue — owner: "the soft ring … I want
/// the soft look"): the tasbeeh grey-blue in light mode (NeuRing / NeuDarkShad / NeuLightShad), charcoal in dark.
enum WatchNeu {
    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.10) : Color(red: 0.890, green: 0.898, blue: 0.933)
    }
    static func darkShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.75) : Color.black.opacity(0.25)
    }
    static func lightShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.white
    }
    /// Every page wears the soft surface, as the phone's Salah, Zikr and tasbeeh pages do.
    static func page(_ scheme: ColorScheme) -> Color { bg(scheme) }
}

/// The soft ring's raised band (CircleTheme.track with `softRing`): the page's surface, lifted — shade down-right,
/// light up-left.
struct WatchSoftBand: View {
    var width: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .stroke(WatchNeu.bg(scheme), lineWidth: width)
            .shadow(color: WatchNeu.darkShadow(scheme), radius: width * 0.6, x: width * 0.3, y: width * 0.3)
            .shadow(color: WatchNeu.lightShadow(scheme), radius: width * 0.9, x: -width * 0.3, y: -width * 0.3)
    }
}

struct WatchRingFace: View {
    /// The iPhone app (Explore): timer-driven gauges render only inside a widget, so they're drawn from now there.
    /// Never set on the watch.
    nonisolated(unsafe) static var drawsStatically = false
    let prayer: WatchPrayer
    let current: Bool
    let now: Date
    /// 1.1 the big ring, 0.55 the small one over the list.
    var k: CGFloat = 1.1
    /// The tap's flip: time left / until instead of "ends" / "at".
    var showLeft = false
    /// The hold to mark it, 0…1: the arc swells and glows.
    var holdFill: CGFloat = 0
    private var band: CGFloat { 5.5 * k }

    private var elapsed: Double {
        guard current, prayer.end > prayer.start else { return 0 }
        return max(0, min(1, now.timeIntervalSince(prayer.start) / prayer.end.timeIntervalSince(prayer.start)))
    }

    /// "31m left" / "1h 5m left".
    private var leftText: String {
        let minutes = max(0, Int(prayer.end.timeIntervalSince(now) / 60))
        if minutes < 1 { return "<1m left" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m left" : "\(minutes)m left"
    }

    /// Before it starts: "in 5m" / "in 1h 51m", the phone's `timeUntilStart` (to the minute: the
    /// page redraws once a minute).
    private var untilText: String { Self.until(prayer.start, now: now) }

    /// 2 on, 3.5 off, fitted to the ring: a whole number of them round it.
    static func fittedDashes(diameter: CGFloat) -> StrokeStyle {
        let period: CGFloat = 5.5
        let circumference = CGFloat.pi * max(diameter, 1)
        let fitted = circumference / max((circumference / period).rounded(), 1)
        return StrokeStyle(lineWidth: 1.25, dash: [fitted * 2 / 5.5, fitted * 3.5 / 5.5])
    }

    /// A prayer's last hour, still not marked: time left is the default and the tap flips to "ends …", staying there
    /// (the phone's PrayerTimeLine, `lastHourLeft`; owner: "in the last 60 minutes, it displays the time left").
    private var lastHour: Bool { Self.lastHour(prayer, current: current, now: now) }
    static func lastHour(_ prayer: WatchPrayer, current: Bool, now: Date) -> Bool { current && prayer.end.timeIntervalSince(now) <= 60 * 60 }
    static func until(_ start: Date, now: Date) -> String {
        let minutes = max(0, Int(start.timeIntervalSince(now) / 60))
        if minutes < 1 { return "in <1m" }
        return minutes >= 60 ? "in \(minutes / 60)h \(minutes % 60)m" : "in \(minutes)m"
    }

    var body: some View {
        ZStack {
            // The phone's soft ring (its public look): a raised band in the page's surface, the arc a fine round band
            // the same width with its own glow; a prayer still to come draws its dashes inside the band.
            WatchSoftBand(width: band)
            if !current {
                // The phone's fix (UpcomingTrack.style(diameter:)): a whole number of dashes round the ring, so the
                // last doesn't run into the first at 3 o'clock.
                GeometryReader { g in
                    Circle().stroke(Color.primary.opacity(0.45), style: Self.fittedDashes(diameter: g.size.width))
                }
            }
            // Holding to mark: the score arc itself swells and glows in its own colour (no green —
            // nothing may suggest a grade the prayer doesn't have; owner).
            let scoreColor = WatchScoring.color(start: prayer.start, end: prayer.end, at: now)
            Circle()
                .trim(from: 0, to: elapsed)
                .stroke(scoreColor, style: StrokeStyle(lineWidth: band + 3.5 * holdFill * k, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: scoreColor.opacity(0.45 + 0.25 * holdFill), radius: (4 + 4 * holdFill) * k)
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: WatchPrayers.symbol(prayer.name))
                        .font(.system(size: 13 * k, weight: .light))
                    Text(prayer.name)
                        .font(.system(size: 19 * k, weight: .light, design: .rounded))
                }
                .foregroundStyle(current ? Color.primary : Color.primary.opacity(0.55))
                .overlay(alignment: .top) {
                    if !current {
                        Text("next")
                            .font(.system(size: 7 * max(k, 0.8), weight: .medium, design: .rounded))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .offset(y: -14 * k)
                    }
                }
                Group {
                    // Tap flips it, in both states, like the phone's circle.
                    if current {
                        if showLeft != lastHour { Text(leftText) } else { Text("ends ") + Text(prayer.end, style: .time) }
                    } else {
                        if showLeft { Text(untilText) } else { Text("at ") + Text(prayer.start, style: .time) }
                    }
                }
                .font(.system(size: 11 * max(k, 0.8), weight: .light, design: .rounded))
                // The last hour's time left in the name's colour, not grey (owner: "a little more prominent", as on
                // the phone).
                .foregroundStyle(current && lastHour && !showLeft ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
            }
        }
    }
}
