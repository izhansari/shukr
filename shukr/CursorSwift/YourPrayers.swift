//
//  YourPrayers.swift
//  shukr
//
//  Prayer scores as "Your prayers" (prayer-metrics rethink, build plan phase 3; the owner's pick A, 2026-10-20: one ring at
//  the top, the same 35-arc language as Journey's week). No 0–100: each prayer's last 7 days as seven slivers in its fifth,
//  "29 of 35 in their time" in the middle; a prayer open, "4 of 7 in its time" and "usually by 6:00 · 4 min from your best
//  month". The page's motion (the row rising into the header, the back dial, the fifths' taps) is PrayerScoresPage's, as
//  built: only what's drawn changes, behind MetricsLook. Every count from PrayerMetrics.recent (Fable's data layer).
//

import SwiftUI

/// The five prayers' last 7 days (PrayerMetrics.recent), read off the main thread when the log changes.
@MainActor @Observable final class YourPrayersRecent {
    static let shared = YourPrayersRecent()
    private(set) var byName: [String: PrayerMetrics.PrayerRecent] = [:]
    @ObservationIgnored private var readFor: UUID?
    /// The latest read: an older one landing after it is dropped (Frank's check: a version change, then Excused.changed).
    @ObservationIgnored private var token = 0

    /// Reads them for `log` once per version (a reload under the same log costs nothing).
    func read(_ log: JourneyLog?, force: Bool = false) {
        guard let log, force || readFor != log.version else { return }
        readFor = log.version
        token += 1
        let mine = token, excused = Excused.Days(), now = Date()
        Task.detached(priority: .userInitiated) {
            var out: [String: PrayerMetrics.PrayerRecent] = [:]
            for name in JourneyLog.names { out[name] = PrayerMetrics.recent(name, in: log, excused: excused, now: now) }
            await MainActor.run { if mine == self.token, out != self.byName { self.byName = out } }
        }
    }

    var inTime: Int { byName.values.reduce(0) { $0 + $1.inTime } }
    var asked: Int { byName.values.reduce(0) { $0 + $1.asked } }

    /// "usually by 6:00 · 4 min from your best month" (nil before there's a usual).
    func usualWords(_ name: String) -> String? {
        guard let r = byName[name], let clock = r.usualClock else { return nil }
        var words = "Usually by \(clock.formatted(date: .omitted, time: .shortened))"
        if let m = r.minutesFromBestMonth, let best = r.bestMonth {
            words += m == 0 ? " · as in your best month" : " · \(m) min from your best month (\(best.start.formatted(.dateTime.month(.abbreviated))))"
        }
        return words
    }
}

/// The page's ring: five fifths (DayRing's places, order and taps), each its prayer's last 7 days as seven slivers in their
/// states — prayed in its grade colour, not marked a faint track, no record dotted. Open, its fifth stays and the rest fade.
struct YourPrayersRing: View {
    let recent: [String: PrayerMetrics.PrayerRecent]
    let picked: Int?
    let onPick: (Int) -> Void
    @Environment(\.circleTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Thicker than DayRing's half band, tighter gaps: at 70 % in the header, seven thin slivers read as a dashed (to come)
        // ring (Zoe's sim check).
        let width = theme.arc.width * 0.78
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = 100
            let ink = scheme == .dark ? Color.white : Color.black
            for (i, name) in DayRing.order.enumerated() {
                let from = (Double(i) / 5 + DayRing.gap) * 360, to = (Double(i + 1) / 5 - DayRing.gap) * 360
                let sliver = (to - from) / 7, gap = 0.9
                let days = recent[name]?.last7 ?? []
                let on = picked == nil || picked == i
                for d in 0..<7 {
                    let a0 = from + Double(d) * sliver + gap / 2 - 90, a1 = a0 + sliver - gap
                    var p = Path()
                    p.addArc(center: c, radius: r, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
                    let state: PrayerState?? = days.indices.contains(d) ? days[d] : nil
                    var shading = ctx
                    shading.opacity = on ? 1 : 0.25
                    switch state {
                    case .some(.some(let s)):
                        if let color = s.ringColor {
                            shading.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                        } else if s == .excused {
                            shading.stroke(p, with: .color(Color(red: 0.55, green: 0.62, blue: 0.75).opacity(0.38)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                        } else {
                            shading.stroke(p, with: .color(ink.opacity(s == .toCome ? 0.07 : 0.17)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                        }
                    case .some(.none):   // no record that day: dotted
                        shading.stroke(p, with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: width * 0.45, lineCap: .round, dash: [0.1, 5]))
                    case .none:
                        shading.stroke(p, with: .color(ink.opacity(0.07)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
                    }
                }
            }
        }
        .frame(width: 200 + width, height: 200 + width)
        .frame(width: 200, height: 200)
        .animation(.smooth(duration: CircleMotion.quick), value: picked)
        // Only the band takes a tap (DayRing's way).
        .contentShape(Circle().stroke(lineWidth: 46))
        .gesture(SpatialTapGesture().onEnded { tap in
            let dx = tap.location.x - 100, dy = tap.location.y - 100
            var turn = atan2(dx, -dy) / (2 * .pi)
            if turn < 0 { turn += 1 }
            onPick(min(Int(turn * 5), 4))
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayRing.order.map { name in
            guard let r = recent[name] else { return "\(name): no record yet" }
            return "\(name): in its time \(r.inTime) of \(r.asked)"
        }.joined(separator: ", "))
    }
}
