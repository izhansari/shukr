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


/// A prayer window's card (Lock Screen) and Dynamic Island. Its views (and `LATuning`, the look's numbers) live in
/// SharedTargetForIntents.swift so the app's DEBUG tuner can preview the very same card.
struct PrayerWindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerWindowAttributes.self) { context in
            LALockCard(state: context.state, n: context.attributes.n, stale: context.isStale)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale && s.markedAt == nil
            let n = context.attributes.n
            let t = LATuning.current
            return DynamicIsland {
                // The whole row under the camera (the bottom region): beside it iOS put the ring + name below the camera
                // but the ✓ beside it, so they never lined up (the sim's island, 2026-10-11).
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            LAEnds(state: s, stale: stale) { e in LAIslandRingAndName(state: s, ended: e, t: t) }
                            Spacer(minLength: 0)
                            LAIslandTrailing(state: s, n: n, ended: stale, t: t, live: true)
                        }
                        .padding(.horizontal, 2)   // (−10 on the left cut the ring off — owner)
                        // The bar's room is kept before marking too: the island growing to fit it redrew the whole island in a
                        // cross-fade (the sim); same size, iOS keeps the ring and name and swaps only what changed (owner).
                        ZStack {
                            Color.clear.frame(height: 4)
                            LADismissBar(state: s).transition(.opacity)
                        }
                        .padding(.horizontal, 24)   // iOS's own bottom margin: at 6 pt it cut the bar off
                    }
                    .environment(\.laInstantGates, true)
                }
            } compactLeading: {
                LACompactLeading(state: s, stale: stale, t: t).environment(\.laInstantGates, true)
            } compactTrailing: {
                LAEnds(state: s, stale: stale) { e in LACompactTrailing(state: s, ended: e) }.environment(\.laInstantGates, true)
            } minimal: {
                LAEnds(state: s, stale: stale) { e in LAFoldedRing(state: s, ended: e, t: t) }
                    .environment(\.laInstantGates, true)
            }
        }
    }
}
