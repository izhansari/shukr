//
//  shukrWidgetLiveActivity.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import ActivityKit
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
/// DEBUG Live Activity research (MY4R): what a prayer window could look like — the app's soft ring filling live (its
/// colours laid out by where in the window they apply, revealed by the timer-driven fill), the time left, Mark prayed;
/// once marked, the post-salah photo and tasbeeh.
struct LATestLiveActivity: Widget {
    static let sage = Color(red: 0.43, green: 0.62, blue: 0.5)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LATestAttributes.self) { context in
            let s = context.state
            HStack(spacing: 14) {
                LAWindowRing(state: s, size: 56, symbolSize: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.label).font(.system(.title3, design: .rounded).weight(.semibold))
                    if let at = s.markedAt {
                        Text("Prayed \(at.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        // The countdown on its own line (a timer Text takes all the width it's given), "ends" under it.
                        Text(timerInterval: s.start...s.end, countsDown: true)
                            .monospacedDigit().font(.subheadline.weight(.medium))
                        Text("ends \(s.end.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                LAActions(state: s, n: context.attributes.n, compact: false)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .activityBackgroundTint(Color(.systemBackground).opacity(0.55))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LAWindowRing(state: s, size: 52, symbolSize: 17).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(s.label).font(.system(.headline, design: .rounded))
                        Text(s.markedAt == nil ? "ends \(s.end.formatted(date: .omitted, time: .shortened))"
                                               : "Prayed \(s.markedAt!.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.markedAt == nil {
                        Text(timerInterval: s.start...s.end, countsDown: true)
                            .monospacedDigit().font(.system(.title3, design: .rounded))
                            .frame(maxWidth: 72).padding(.trailing, 4)
                    } else {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Self.sage)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LAActions(state: s, n: context.attributes.n, compact: true).padding(.top, 4)
                }
            } compactLeading: {
                LAWindowRing(state: s, size: 22, symbolSize: 8)
            } compactTrailing: {
                if s.markedAt == nil {
                    Text(timerInterval: s.start...s.end, countsDown: true)
                        .monospacedDigit().font(.system(size: 14, weight: .medium, design: .rounded))
                        .frame(maxWidth: 48)
                } else {
                    Image(systemName: "checkmark").foregroundStyle(Self.sage)
                }
            } minimal: {
                LAWindowRing(state: s, size: 22, symbolSize: 8)
            }
            .keylineTint(Self.sage)
        }
    }
}

/// Mark prayed (a capsule) — or, once marked, the photo and tasbeeh round buttons.
private struct LAActions: View {
    let state: LATestAttributes.ContentState
    let n: Int
    let compact: Bool
    var body: some View {
        if state.markedAt == nil {
            Button(intent: LATestMarkIntent(n: n)) {
                Label("Mark prayed", systemImage: "checkmark")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .frame(maxWidth: compact ? .infinity : nil)
                    .background(Capsule().fill(LATestLiveActivity.sage.opacity(0.25)))
                    .foregroundStyle(LATestLiveActivity.sage)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                round("camera.fill", "Photo", LATestOpenIntent(what: "Photo"))
                round("circle.grid.cross.fill", "Tasbih", LATestOpenIntent(what: "Tasbih"))
            }
            .frame(maxWidth: compact ? .infinity : nil)
        }
    }
    private func round(_ icon: String, _ label: String, _ intent: LATestOpenIntent) -> some View {
        Button(intent: intent) {
            Group {
                if compact {
                    Label(label, systemImage: icon).font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: .infinity)
                } else {
                    Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 40, height: 40)
                }
            }
            .background(Capsule().fill(LATestLiveActivity.sage.opacity(0.25)))
            .foregroundStyle(LATestLiveActivity.sage)
        }
        .buttonStyle(.plain)
    }
}

/// The app's soft ring for one window: a faint band, and the arc in the colour the score would be at each point of the
/// window (an angular gradient with hard stops), shown only up to now by the system-driven `ProgressView(timerInterval:)`
/// used as a mask (`PrayersWidget.LiveArc`'s trick). Marked: the full ring in the score it got.
struct LAWindowRing: View {
    let state: LATestAttributes.ContentState
    let size: CGFloat
    let symbolSize: CGFloat
    private let design: CGFloat = 98

    var body: some View {
        ZStack {
            Group {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 6).frame(width: 90, height: 90)
                if let at = state.markedAt {
                    Circle().stroke(PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at)),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 90, height: 90)
                } else {
                    // Trimmed off the seam at the top: the stock ring's round start showed the gradient's last colour there.
                    Circle()
                        .trim(from: 0.006, to: 0.98)
                        .rotation(.degrees(-90))
                        .stroke(gradient, style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                        .frame(width: 90, height: 90)
                        .mask { liveMask }
                }
            }
            .frame(width: design, height: design)
            .scaleEffect(size / design)
            Image(systemName: state.markedAt == nil ? state.symbol : "checkmark")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
    }

    /// Hard colour stops: the score colour at each 1/48 of the window.
    private var gradient: AngularGradient {
        let steps = 48
        let span = state.end.timeIntervalSince(state.start)
        var stops: [Gradient.Stop] = []
        for i in 0..<steps {
            let at = state.start.addingTimeInterval(span * (Double(i) + 0.5) / Double(steps))
            let c = PrayerScoring.color(for: PrayerScoring.score(start: state.start, end: state.end, markedAt: at))
            stops.append(.init(color: c, location: Double(i) / Double(steps)))
            stops.append(.init(color: c, location: Double(i + 1) / Double(steps)))
        }
        return AngularGradient(stops: stops, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    private var liveMask: some View {
        ZStack {
            Color.black
            ProgressView(timerInterval: state.start...state.end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(.white)
                .labelsHidden()
        }
        .frame(width: design, height: design)
        .compositingGroup()
        .brightness(-0.35)
        .contrast(3)
        .luminanceToAlpha()
    }
}
#endif
