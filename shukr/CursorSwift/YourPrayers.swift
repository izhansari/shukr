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

/// One prayer's window as the page's hero (owner, 2026-10-20, on Zoe's demo ring: "now show this in the hero for the
/// individual prayer page"): its window in thirds (Opening · Middle · Closing, faint), lit from its start to today's mark
/// with a hollow dot there, a tick where you usually pray it (the span's place in the window), today's time and its place in
/// the middle. Read-only (the editor's PrayerWindowRing is the one you drag); the same arc style.
struct PrayerWindowHero: View {
    let name: String
    /// Where you usually pray it (0 as it begins, 1 as it ends); nil: no tick.
    let usualShare: Double?
    @Environment(\.circleTheme) private var theme

    private static let side: CGFloat = 200
    private static let gap = 2.4

    /// Today's window and mark (Journey's log, which the page already has).
    private var today: (start: Date, end: Date, markedAt: Date?, mark: JourneyLog.Mark)? {
        guard let log = JourneyStore.shared.log, let i = JourneyLog.names.firstIndex(of: name) else { return nil }
        let day = log.day(PrayerDay.start())
        guard let slot = day.slots[i] else { return nil }
        return (slot.start, slot.end, slot.markedAt, day.marks[i])
    }

    var body: some View {
        let r: CGFloat = 92, w = theme.arc.width
        let t = today
        let total = t.map { max($0.end.timeIntervalSince($0.start), 1) } ?? 1
        let markShare: Double? = t.flatMap { tt in tt.markedAt.map { $0.timeIntervalSince(tt.start) / total } }
        let lit = min(max(markShare ?? 0, 0), 1) * 360
        let opening = PrayerScoring.openingShare, mid = opening + (1 - opening) / 2
        let zones: [(Double, Double, Double)] = [(0, opening * 360, 1), (opening * 360, mid * 360, 0.9), (mid * 360, 360, 0.7)]
        ZStack {
            ForEach(Array(zones.enumerated()), id: \.offset) { _, z in
                let color = PrayerScoring.color(for: z.2)
                let a0 = z.0 + Self.gap / 2, a1 = z.1 - Self.gap / 2
                arc(a0, a1).stroke(color.opacity(0.16), style: StrokeStyle(lineWidth: w, lineCap: theme.arc.cap))
                if markShare != nil, min(a1, lit) > a0 + 0.5 {
                    arc(a0, min(a1, lit)).stroke(color, style: StrokeStyle(lineWidth: w, lineCap: theme.arc.cap))
                }
            }
            .frame(width: r * 2, height: r * 2)
            // Your usual: a tick across the band, its word inside the ring (outside, it ran off the edge at 70 %).
            if let u = usualShare {
                let a = u * 360 * .pi / 180
                Capsule().fill(Color.secondary).frame(width: 2, height: w + 10)
                    .offset(y: -r).rotationEffect(.radians(a))
                Text("usual").font(.system(size: 11, weight: .light, design: .rounded)).foregroundStyle(.secondary)
                    .offset(x: (r - w - 12) * sin(a), y: -(r - w - 12) * cos(a))
            }
            if let m = markShare {
                let a = min(max(m, 0), 1) * 360 * .pi / 180
                let color = t.flatMap { $0.mark.score }.map { PrayerScoring.color(for: $0) } ?? .gray
                Circle().fill(theme.surface)
                    .overlay(Circle().strokeBorder(color, lineWidth: 2.8))
                    .frame(width: 15, height: 15)
                    .offset(x: r * sin(a), y: -r * cos(a))
            }
            centre(t)
        }
        .frame(width: Self.side, height: Self.side)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    /// The hour and minutes in the user's 12 / 24-hour setting, no AM / PM (it fits the middle; the window says when).
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        let format = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm"
        f.dateFormat = format.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return f
    }()

    @ViewBuilder private func centre(_ t: (start: Date, end: Date, markedAt: Date?, mark: JourneyLog.Mark)?) -> some View {
        let (big, small): (String, String) = {
            guard let t else { return ("–", "today · not yet") }   // the day's rows aren't made yet
            switch t.mark {
            case .done(let score):
                let word = t.markedAt.map { $0 > t.end } == true ? "made up" : PrayerScoring.grade(for: score).rawValue
                return (t.markedAt.map { Self.clock.string(from: $0) } ?? "✓", t.markedAt == nil ? "today · in its time" : "today · \(word)")
            case .missed: return ("–", "today · not marked")
            case .excused: return ("–", "today · excused")
            default: return ("–", Date() < t.start ? "today · to come" : "today · not yet")
            }
        }()
        VStack(spacing: 2) {
            Text(big).font(.system(size: 46, weight: .thin, design: .rounded)).monospacedDigit()
            Text(small).font(.system(size: 15, weight: .light, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private func arc(_ from: Double, _ to: Double) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: 92, y: 92), radius: 92, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
        return p
    }
}
