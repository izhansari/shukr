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
/// DEBUG Live Activity research (MY4R): the prayer window card. Its views (and `LATuning`, the tuner's numbers) live in
/// SharedTargetForIntents.swift so the app's tuner can preview the very same card.
struct LATestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LATestAttributes.self) { context in
            LALockCard(state: context.state, n: context.attributes.n, stale: context.isStale)
        } dynamicIsland: { context in
            let s = context.state
            let stale = context.isStale && s.markedAt == nil
            let n = context.attributes.n
            let t = LATuning.current
            let layout = t.islandLayout ?? 1
            return DynamicIsland {
                // (The island's builder takes no `if`: each region picks its own content.)
                DynamicIslandExpandedRegion(.leading, priority: layout == 2 ? 1 : 0) {
                    LAEnds(state: s, stale: stale) { e in
                        if layout == 0 { LAIslandLeading(state: s, ended: e, t: t) } else { LAIslandRingAndName(state: s, ended: e, t: t) }
                    }
                    .frame(maxWidth: layout == 0 ? nil : .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.center) {
                    if layout == 0 {
                        LAEnds(state: s, stale: stale) { e in LANameLines(state: s, ended: e, big: false, t: t) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                DynamicIslandExpandedRegion(.trailing, priority: layout == 2 ? 1 : 0) {
                    LAIslandTrailing(state: s, n: n, ended: stale, t: t, live: true)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LADismissBar(state: s).padding(.horizontal, 24)
                }
            } compactLeading: {
                LACompactLeading(state: s, stale: stale, t: t)
            } compactTrailing: {
                LAEnds(state: s, stale: stale) { e in LACompactTrailing(state: s, ended: e) }
            } minimal: {
                LAEnds(state: s, stale: stale) { e in LARing(state: s, ended: e, size: 22, onIsland: true, t: t) }
            }
        }
    }
}
#endif
