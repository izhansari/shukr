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
/// DEBUG Live Activity research (MY4R): a prayer window in the widget's own look (owner: "not up to par with our app's
/// aesthetic … borrow from the widget"): the soft band + live arc, the ring's light rounded type, the soft surface, and
/// round SF Symbol buttons — the widget's mark circle; after marking, camera and the Zikr tab's circle.hexagongrid.
struct LATestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LATestAttributes.self) { context in
            LALockCard(state: context.state, n: context.attributes.n)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LARing(state: s, size: 64, onIsland: true).padding(.leading, 6).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    LANameLine(state: s, big: true).padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LAButtons(state: s, n: context.attributes.n, size: 40).padding(.trailing, 6).padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if s.markedAt == nil {
                        LACountdown(state: s, size: 13).padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                LARing(state: s, size: 20, showsSymbol: false, onIsland: true)
            } compactTrailing: {
                if s.markedAt == nil {
                    Text(timerInterval: s.start...s.end, countsDown: true)
                        .monospacedDigit().font(.system(size: 14, weight: .light, design: .rounded))
                        .frame(maxWidth: 46)
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 14, weight: .light))
                }
            } minimal: {
                LARing(state: s, size: 20, showsSymbol: false, onIsland: true)
            }
        }
    }
}

/// The Lock Screen card, the widget's ring and type: the ring with the symbol, name and "ends …" inside (as on the
/// widget), the time left beside it in the ring's light rounded type, the round mark button. In the app's look.
private struct LALockCard: View {
    let state: LATestAttributes.ContentState
    let n: Int
    var body: some View {
        if let dark = state.dark {
            LALockCardBody(state: state, n: n).environment(\.colorScheme, dark ? .dark : .light)
        } else {
            LALockCardBody(state: state, n: n)   // the app follows the phone
        }
    }
}

private struct LALockCardBody: View {
    let state: LATestAttributes.ContentState
    let n: Int
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                LARing(state: state, size: 96, showsSymbol: false)
                LARingCenter(state: state)
            }
            VStack(alignment: .leading, spacing: 0) {
                if state.markedAt == nil {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 30, weight: .light, design: .rounded))
                        .frame(maxWidth: 120, alignment: .leading)
                        .fixedSize()
                    Text("left").font(.system(size: 13, weight: .thin, design: .rounded)).foregroundStyle(.secondary)
                } else {
                    Text("prayed").font(.system(size: 13, weight: .thin, design: .rounded)).foregroundStyle(.secondary)
                    Text(state.markedAt!.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 26, weight: .light, design: .rounded))
                }
            }
            Spacer(minLength: 0)
            LAButtons(state: state, n: n, size: 46)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 18).padding(.vertical, 14)
        .activityBackgroundTint(WidgetSoft.surface(scheme))
        .activitySystemActionForegroundColor(.primary)
    }
}

/// Inside the ring, as on the widget: the symbol and name in light rounded type, "ends 5:42 PM" thin under it.
private struct LARingCenter: View {
    let state: LATestAttributes.ContentState
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: state.symbol).font(.system(size: 11, weight: .light))
                Text(state.label).font(.system(size: 15, weight: .light, design: .rounded))
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            Text(state.markedAt == nil ? "ends \(state.end.formatted(date: .omitted, time: .shortened))" : "done")
                .font(.system(size: 10, weight: .thin, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }
}

/// "Asr" in the ring's light rounded type and, under it, when it ends (or when it was prayed) — the Dynamic Island.
private struct LANameLine: View {
    let state: LATestAttributes.ContentState
    let big: Bool
    var body: some View {
        VStack(alignment: .center, spacing: 1) {
            Text(state.label).font(.system(size: 18, weight: .light, design: .rounded))   // the symbol is in the ring
            Text(state.markedAt.map { "prayed \($0.formatted(date: .omitted, time: .shortened))" }
                 ?? "ends \(state.end.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12, weight: .thin, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }
}

/// The time left, light and rounded, with a thin "left".
private struct LACountdown: View {
    let state: LATestAttributes.ContentState
    let size: CGFloat
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(timerInterval: state.start...state.end, countsDown: true)
                .monospacedDigit().font(.system(size: size + 6, weight: .light, design: .rounded))
                .multilineTextAlignment(.trailing)
                .frame(width: 70, alignment: .trailing)
            Text("left").font(.system(size: size, weight: .thin, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

/// Round SF Symbol buttons in a soft circle: the widget's mark (circle); once prayed, camera and the Zikr symbol.
private struct LAButtons: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let size: CGFloat
    var body: some View {
        HStack(spacing: 10) {
            if state.markedAt == nil {
                LARoundButton(intent: LATestMarkIntent(n: n), symbol: "circle", size: size)
            } else {
                LARoundButton(intent: LATestOpenIntent(what: "Photo"), symbol: "camera", size: size)
                LARoundButton(intent: LATestOpenIntent(what: "Tasbih"), symbol: "circle.hexagongrid", size: size)
            }
        }
    }
}

private struct LARoundButton<I: AppIntent>: View {
    let intent: I
    let symbol: String
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(WidgetSoft.surface(scheme))
                        .shadow(color: WidgetSoft.shade(scheme), radius: 3, x: 1.5, y: 1.5)
                        .shadow(color: WidgetSoft.light(scheme), radius: 3, x: -1.5, y: -1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

/// The widget's ring (`WidgetSoftBand` + `LiveArc`), drawn at its 90 pt size and scaled. One colour at a time, as in
/// the app: the arc for each grade lies over the one before and is switched on at the moment that grade starts
/// (`PrayerScoring.gradeChanges`) by a second timer-driven mask — no update needed. Prayed: the whole ring in its score.
struct LARing: View {
    let state: LATestAttributes.ContentState
    let size: CGFloat
    var showsSymbol = true
    /// On the Dynamic Island (always black): a faint light track, as the app's dark ring, instead of the soft band.
    var onIsland = false

    var body: some View {
        ZStack {
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
                } else {
                    // One layer per grade, stacked: each later grade covers the one before from the moment it starts.
                    let changes = PrayerScoring.gradeChanges(start: state.start, end: state.end)
                    PrayersWidgetView.LiveArc(start: state.start, end: state.end, color: colorAt(state.start), soft: true)
                    ForEach(Array(changes.enumerated()), id: \.offset) { _, t in
                        PrayersWidgetView.LiveArc(start: state.start, end: state.end, color: colorAt(t.addingTimeInterval(1)), soft: true)
                            .mask { LASwitch(at: t) }
                    }
                }
            }
            .frame(width: 90, height: 90)
            .scaleEffect(size / 90)
            .frame(width: size, height: size)
            if showsSymbol && size >= 60 {
                Image(systemName: state.markedAt == nil ? state.symbol : "checkmark")
                    .font(.system(size: size * 0.2, weight: .light))
            }
        }
    }

    private func colorAt(_ t: Date) -> Color {
        PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: t))
    }
}

/// Nothing until `at`, then (within a second) the whole square: a stock timer bar over a 1 s interval, stretched over
/// the ring's frame and thresholded like `LiveArc`'s mask (its grey track → nothing, its fill → everything), so the
/// layer under it — cap and glow included — is fully covered once its grade starts.
private struct LASwitch: View {
    let at: Date
    var body: some View {
        ZStack {
            Color.black
            ProgressView(timerInterval: at...at.addingTimeInterval(1), countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
                .tint(.white)
                .labelsHidden()
                .frame(width: 98)
                .scaleEffect(x: 1, y: 60)
        }
        .frame(width: 98, height: 98)
        .clipped()
        .compositingGroup()
        .brightness(-0.35)
        .contrast(3)
        .luminanceToAlpha()
    }
}
#endif
