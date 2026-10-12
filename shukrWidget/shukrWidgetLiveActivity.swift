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
            let layout = t.islandArrangement ?? 3
            return DynamicIsland {
                // (The island's builder takes no `if`: each region picks its own content.) Layout 3, the default: the
                // whole row in the bottom region, under the camera — in 1 iOS put the ring + name below the camera (too
                // wide beside it) but the ✓ beside it, so they never lined up (the sim's island, 2026-10-11).
                DynamicIslandExpandedRegion(.leading, priority: layout == 2 ? 1 : 0) {
                    if layout != 3 {
                        LAEnds(state: s, stale: stale) { e in
                            if layout == 0 { LAIslandLeading(state: s, ended: e, t: t) } else { LAIslandRingAndName(state: s, ended: e, t: t) }
                        }
                        .frame(maxWidth: layout == 0 ? nil : .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if layout == 0 {
                        LAEnds(state: s, stale: stale) { e in LANameLines(state: s, ended: e, big: false, t: t) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DynamicIslandExpandedRegion(.trailing, priority: layout == 2 ? 1 : 0) {
                    if layout != 3 {
                        LAIslandTrailing(state: s, n: n, ended: stale, t: t, live: true)
                            .dynamicIsland(verticalPlacement: .belowIfTooWide)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if layout == 3 {
                            HStack(spacing: 8) {
                                LAEnds(state: s, stale: stale) { e in LAIslandRingAndName(state: s, ended: e, t: t) }
                                Spacer(minLength: 0)
                                LAIslandTrailing(state: s, n: n, ended: stale, t: t, live: true)
                            }
                            .padding(.leading, -10).padding(.trailing, 2)   // the region's left margin is wider (the sim's island)
                        }
                        LADismissBar(state: s).padding(.horizontal, 24)   // on the island's bottom edge, as on the card (owner)
                    }
                }
            } compactLeading: {
                LACompactLeading(state: s, stale: stale, t: t)
            } compactTrailing: {
                LAEnds(state: s, stale: stale) { e in LACompactTrailing(state: s, ended: e) }
            } minimal: {
                LAEnds(state: s, stale: stale) { e in LARing(state: s, ended: e, size: 22, onIsland: true, t: t) }
            }
            .contentMargins(.bottom, 9, for: .expanded)   // the 15 s bar near the island's bottom edge
        }
    }
}
