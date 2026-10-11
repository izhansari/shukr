//
//  shukrWidgetLiveActivity.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

struct shukrWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct shukrWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: shukrWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension shukrWidgetAttributes {
    fileprivate static var preview: shukrWidgetAttributes {
        shukrWidgetAttributes(name: "World")
    }
}

extension shukrWidgetAttributes.ContentState {
    fileprivate static var smiley: shukrWidgetAttributes.ContentState {
        shukrWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: shukrWidgetAttributes.ContentState {
         shukrWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: shukrWidgetAttributes.preview) {
   shukrWidgetLiveActivity()
} contentStates: {
    shukrWidgetAttributes.ContentState.smiley
    shukrWidgetAttributes.ContentState.starEyes
}


#if DEBUG
/// DEBUG Live Activity research (MY4R) — look G (owner, decision live-activity-look = G; Frank's brief
/// board/mocks/live-activity-looks/brief-sami.md): the app's soft card in shukr's own look; the Salah ring in the middle
/// (symbol, name, time left inside); two grey lines on the left; SF Symbols only on the right in the soft round button;
/// the score colour washing up from the bottom-left. Ended = grey dashes + a grey dashed circle (Qaza), never red.
/// Everything that changes with time (the grade, its colour, red in the last half hour, ended) changes by itself:
/// timer-driven gates (`LAGate`) and iOS's own stale flag — no update from shukr.
struct LATestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LATestAttributes.self) { context in
            LALockCard(state: context.state, n: context.attributes.n, ended: context.isStale)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale && s.markedAt == nil
            let n = context.attributes.n
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LAEnds(state: s, stale: stale) { e in LASideRing(state: s, ended: e, size: 62, onIsland: true) }
                        .padding(.leading, 6).padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    LAEnds(state: s, stale: stale) { e in LANameLines(state: s, ended: e, big: false) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LAEnds(state: s, stale: stale) { e in LAButtons(state: s, n: n, ended: e, size: 38, onIsland: true) }
                        .padding(.trailing, 6).padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LADismissBar(state: s).padding(.horizontal, 24)
                }
            } compactLeading: {
                LAEnds(state: s, stale: stale) { e in LARing(state: s, ended: e, size: 22, onIsland: true) }
                    .overlay { Image(systemName: s.symbol).font(.system(size: 8, weight: .medium)) }
            } compactTrailing: {
                LAEnds(state: s, stale: stale) { e in LACompactTrailing(state: s, ended: e) }
            } minimal: {
                LAEnds(state: s, stale: stale) { e in LARing(state: s, ended: e, size: 22, onIsland: true) }
            }
        }
    }
}

/// The running look until the window ends, the ended look from then on — by itself (timer gates), because iOS's stale
/// flag didn't flip at the stale date (sim, 2026-10-11: still not stale 70 s after, with shukr watching). Marked, or
/// already stale: just that one look. Both looks keep the round button in the same place, so a tap always lands.
struct LAEnds<Content: View>: View {
    let state: LATestAttributes.ContentState
    let stale: Bool
    @ViewBuilder let content: (_ ended: Bool) -> Content
    var body: some View {
        if state.markedAt != nil {
            content(false)
        } else if stale {
            content(true)
        } else {
            ZStack {
                content(false).mask { LAGate(from: nil, until: state.end) }
                content(true).mask { LAGate(from: state.end, until: nil) }
            }
        }
    }
}

// MARK: - Lock Screen card

private struct LALockCard: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let ended: Bool
    var body: some View {
        // Always dark (owner, 2026-10-11: "the dark ones look sleek, modern and not loud; the light ones … soft and playful
        // and colour in your face").
        LAEnds(state: state, stale: ended) { e in LALockCardBody(state: state, n: n, ended: e) }
            .environment(\.colorScheme, .dark)
    }
}

/// Look D's layout in the app's soft look (owner, 2026-10-11): the soft ring on the left with the prayer's symbol
/// inside (✓ once prayed), the name and two lines beside it, the soft round buttons on the right, the score colour
/// glowing out from the ring, dark; once prayed, the 15 s bar along the bottom.
private struct LALockCardBody: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let ended: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 16) {
            LASideRing(state: state, ended: ended, size: 78, onIsland: false)
            LANameLines(state: state, ended: ended, big: true)
            Spacer(minLength: 0)
            LAButtons(state: state, n: n, ended: ended, size: 44, onIsland: false)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        // Our own solid surface under the glow: iOS draws `activityBackgroundTint` see-through, so the wallpaper showed
        // through and turned a red glow pink (owner's phone, 2026-10-11).
        .background {
            ZStack {
                WidgetSoft.surface(scheme)
                LAWash(state: state, ended: ended)
            }
        }
        .overlay(alignment: .bottom) { LADismissBar(state: state).padding(.horizontal, 18).padding(.bottom, 7) }
        .activityBackgroundTint(WidgetSoft.surface(scheme))
        .activitySystemActionForegroundColor(.primary)
    }
}

/// The soft ring with the prayer's symbol inside (a ✓ once prayed).
private struct LASideRing: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let size: CGFloat
    let onIsland: Bool
    var body: some View {
        ZStack {
            LARing(state: state, ended: ended, size: size, onIsland: onIsland)
            Image(systemName: state.markedAt == nil ? state.symbol : "checkmark")
                .font(.system(size: size * 0.24, weight: .light))
                .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .frame(width: size, height: size)
    }
}

/// "Asr" in the ring's light rounded type, then: the time left (red in the last half hour) + "ends 6:48 PM"; prayed:
/// "Prayed 4:31 PM" + "Perfect · 100"; ended: "Asr ended" + "6:48 PM · not marked".
private struct LANameLines: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let big: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ended ? "\(state.label) ended" : state.label)
                .font(.system(size: big ? 24 : 19, weight: .light, design: .rounded))
                .foregroundStyle(ended ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            Group {
                if let at = state.markedAt {
                    let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
                    Text("Prayed \(at.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.primary)
                    Text("\(PrayerScoring.grade(for: score).rawValue) · \(Int((score * 100).rounded()))")
                        .foregroundStyle(.secondary)
                } else if ended {
                    Text("\(state.end.formatted(date: .omitted, time: .shortened)) · not marked")
                        .foregroundStyle(.secondary)
                } else {
                    let lastHalf = state.end.addingTimeInterval(-30 * 60)
                    ZStack(alignment: .leading) {
                        LATimeLeft(end: state.end).foregroundStyle(.primary)
                            .mask { LAGate(from: nil, until: lastHalf) }
                        LATimeLeft(end: state.end).foregroundStyle(.red)
                            .mask { LAGate(from: lastHalf, until: nil) }
                    }
                    Text("ends \(state.end.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: big ? 14 : 12, weight: .regular, design: .rounded))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// The two small grey lines: "ends 6:48 PM" + "<grade> now" (the grade changes by itself); marked: "Prayed 4:31 PM" +
/// "Score 100"; ended: "6:48 PM" + "not marked".
private struct LALeftLines: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let at = state.markedAt {
                Text("Prayed \(at.formatted(date: .omitted, time: .shortened))")
                Text("Score \(Int((PrayerScoring.score(start: state.start, end: state.end, markedAt: at) * 100).rounded()))")
            } else if ended {
                Text(state.end.formatted(date: .omitted, time: .shortened))
                Text("not marked")
            } else {
                Text("ends \(state.end.formatted(date: .omitted, time: .shortened))")
                ZStack(alignment: .leading) {
                    ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                        Text("\(span.grade.rawValue) now").mask { LAGate(from: span.from, until: span.until) }
                    }
                }
            }
        }
        .font(.system(size: 13, weight: .regular, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }
}

/// The Salah ring with the symbol + name inside and, under them, the time left (red in the last half hour), the grade
/// once prayed, or "ended".
private struct LACentreRing: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let size: CGFloat
    let onIsland: Bool
    var body: some View {
        ZStack {
            LARing(state: state, ended: ended, size: size, onIsland: onIsland)
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: state.symbol).font(.system(size: size * 0.12, weight: .light))
                    Text(state.label).font(.system(size: size * 0.17, weight: .regular, design: .rounded))
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Group {
                    if let at = state.markedAt {
                        let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
                        Text(PrayerScoring.grade(for: score).rawValue).foregroundStyle(PrayerScoring.color(for: score))
                    } else if ended {
                        Text("ended").foregroundStyle(.secondary)
                    } else {
                        // The time left, the system's own live relative text; red over it from the last half hour.
                        let lastHalf = state.end.addingTimeInterval(-30 * 60)
                        ZStack {
                            LATimeLeft(end: state.end).foregroundStyle(.secondary)
                                .mask { LAGate(from: nil, until: lastHalf) }
                            LATimeLeft(end: state.end).foregroundStyle(.red)
                                .mask { LAGate(from: lastHalf, until: nil) }
                        }
                    }
                }
                .font(.system(size: size * 0.105, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)   // "1 hour, 14 minutes left" wraps inside the ring
            }
            .padding(.horizontal, size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

/// "2 hours, 36 minutes left" — the system's live offset, hours and minutes only (no seconds), ticking by itself.
private struct LATimeLeft: View {
    let end: Date
    var body: some View {
        Text("\(Text(.currentDate, format: .offset(to: end, allowedFields: [.hour, .minute], maxFieldCount: 2, sign: .never))) left")
    }
}

/// After Mark prayed: how long until the card goes (shukr ends it 15 s after the tap) — a thin sage bar along the
/// bottom, full at the tap and emptying right to left, as the post-salah pill's ring empties. Timer-driven, no updates.
struct LADismissBar: View {
    let state: LATestAttributes.ContentState
    static let seconds: TimeInterval = 15
    var body: some View {
        if let at = state.markedAt {
            ProgressView(timerInterval: at...at.addingTimeInterval(Self.seconds), countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(Color(red: 0.43, green: 0.62, blue: 0.5))
                .labelsHidden()
        }
    }
}

/// The island's small right side: time left; marked → the grade in its colour; ended → "ended".
private struct LACompactTrailing: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    var body: some View {
        Group {
            if let at = state.markedAt {
                let score = PrayerScoring.score(start: state.start, end: state.end, markedAt: at)
                Text(PrayerScoring.grade(for: score).rawValue).foregroundStyle(PrayerScoring.color(for: score))
            } else if ended {
                Text("ended").foregroundStyle(.secondary)
            } else {
                Text(timerInterval: state.start...state.end, countsDown: true).monospacedDigit()
            }
        }
        .font(.system(size: 14, weight: .medium, design: .rounded))
        .frame(maxWidth: 64)
    }
}

/// SF Symbols only, in the app's soft round button: `circle` marks it (as on the widget); prayed → camera + Tasbih (the
/// Zikr tab's symbol); ended → a grey dashed circle, Mark as Qaza (never red — owner).
private struct LAButtons: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let ended: Bool
    let size: CGFloat
    let onIsland: Bool
    var body: some View {
        if state.markedAt != nil {
            VStack(spacing: 8) {
                LARoundButton(intent: LATestOpenIntent(what: "Photo", n: n), symbol: "camera", size: size * 0.86, onIsland: onIsland)
                LARoundButton(intent: LATestOpenIntent(what: "Tasbih", n: n), symbol: "circle.hexagonpath", size: size * 0.86, onIsland: onIsland)
            }
        } else if ended {
            LARoundButton(intent: LATestMarkIntent(n: n), symbol: "circle.dashed", size: size, onIsland: onIsland, dim: true)
        } else {
            LARoundButton(intent: LATestMarkIntent(n: n), symbol: "circle", size: size, onIsland: onIsland)
        }
    }
}

private struct LARoundButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let size: CGFloat
    var onIsland = false
    var dim = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .light))
                .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background {
                    if onIsland {
                        Circle().fill(Color.white.opacity(0.12))
                    } else {
                        Circle().fill(WidgetSoft.surface(scheme))
                            .shadow(color: WidgetSoft.shade(scheme), radius: 3, x: 1.5, y: 1.5)
                            .shadow(color: WidgetSoft.light(scheme), radius: 3, x: -1.5, y: -1.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// The score colour glowing out from the ring (Look D's halo), in the colour of the grade now (it changes by itself);
/// prayed: its score's colour; ended: none.
private struct LAWash: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    var body: some View {
        if let at = state.markedAt {
            wash(PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at)))
        } else if !ended {
            ZStack {
                ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                    wash(span.color).mask { LAGate(from: span.from, until: span.until) }
                }
            }
        }
    }
    private func wash(_ c: Color) -> some View {
        RadialGradient(colors: [c.opacity(0.40), c.opacity(0.12), c.opacity(0)], center: UnitPoint(x: 0.17, y: 0.5), startRadius: 24, endRadius: 230)
    }
}

/// The window's grades in order, each with when it applies.
enum LAGrades {
    struct Span { let grade: PrayerScoring.Grade; let color: Color; let from: Date?; let until: Date? }
    static func spans(_ s: LATestAttributes.ContentState) -> [Span] {
        let changes = PrayerScoring.gradeChanges(start: s.start, end: s.end)
        let starts: [Date?] = [nil] + changes.map { Optional($0) }
        return starts.enumerated().map { i, from in
            // The grade in the middle of its stretch: 1 s after a change, a long window's score is still 0.99999…,
            // which `grade(for:)` counts as Perfect (a 160-min Asr stayed green 40 min in).
            let a = from ?? s.start
            let b = i + 1 < starts.count ? (starts[i + 1] ?? s.end) : s.end
            let at = a.addingTimeInterval(b.timeIntervalSince(a) / 2)
            let score = PrayerScoring.score(start: s.start, end: s.end, markedAt: at)
            return Span(grade: PrayerScoring.grade(for: score), color: PrayerScoring.color(for: score),
                        from: from, until: i + 1 < starts.count ? starts[i + 1] : s.end)
        }
    }
}

/// The widget's ring (`WidgetSoftBand` + `LiveArc`) at its 90 pt size, scaled: one colour at a time — an arc per grade,
/// each shown only while its grade lasts. Prayed: the whole ring in its score. Ended: 8 grey dashes.
struct LARing: View {
    let state: LATestAttributes.ContentState
    let ended: Bool
    let size: CGFloat
    var onIsland = false

    var body: some View {
        ZStack {
            if onIsland {
                Circle().stroke(Color.white.opacity(0.16), lineWidth: 4.5)
            } else {
                WidgetSoftBand(width: 4.5)
            }
            if let at = state.markedAt {
                let c = PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at))
                Circle().stroke(c, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .shadow(color: c.opacity(0.45), radius: 3)
            } else if ended {
                let gap = CGFloat.pi * 90 / 8
                Circle().stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [gap * 0.55, gap * 0.45]))
                    .rotationEffect(.degrees(-90))
            } else {
                ForEach(Array(LAGrades.spans(state).enumerated()), id: \.offset) { _, span in
                    PrayersWidgetView.LiveArc(start: state.start, end: state.end, color: span.color, soft: true)
                        .mask { LAGate(from: span.from, until: span.until).frame(width: 110, height: 110) }
                }
            }
        }
        .frame(width: 90, height: 90)
        .scaleEffect(size / 90)
        .frame(width: size, height: size)
    }
}

/// Visible from `from` (nil = from the start) until `until` (nil = for good), by itself: each edge is a stock timer bar
/// over a 1 s interval stretched over the whole area, thresholded to all-or-nothing. On: black → white as it fills. Off:
/// white → black as it fills (its grey track is pushed up to white first, so it never hides anything before its time).
struct LAGate: View {
    let from: Date?
    let until: Date?
    var body: some View {
        Group {
            if let from { edge(from, fill: .white, ground: .black, lift: -0.35) } else { Color.white }
        }
        .mask {
            if let until { edge(until, fill: .black, ground: .white, lift: 0.2) } else { Color.white }
        }
    }

    private func edge(_ t: Date, fill: Color, ground: Color, lift: Double) -> some View {
        GeometryReader { geo in
            ZStack {
                ground
                ProgressView(timerInterval: t...t.addingTimeInterval(1), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(fill)
                    .labelsHidden()
                    .frame(width: geo.size.width)
                    .scaleEffect(x: 1, y: max(geo.size.height, 4) * 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Light, whatever the card: in dark the stock bar's tint and track resolve differently and the gates
            // stopped switching (the ring stayed green past 30 min on the dark card).
            .environment(\.colorScheme, .light)
            .compositingGroup()
            .brightness(lift)
            .contrast(3)
            .luminanceToAlpha()
        }
    }
}
#endif
