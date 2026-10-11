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
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LAEnds(state: s, stale: stale) { e in LASideRing(state: s, ended: e, size: t.islandRingSize, symbolSize: t.islandRingSize * 0.26, onIsland: true, t: t) }
                        .padding(.leading, 4).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    LAEnds(state: s, stale: stale) { e in LANameLines(state: s, ended: e, big: false, t: t) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LAEnds(state: s, stale: stale) { e in LAGlyphs(state: s, n: n, ended: e, size: t.islandButtonSize, onIsland: true, t: t) }
                        .padding(.trailing, 4).padding(.top, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LADismissBar(state: s).padding(.horizontal, 24)
                }
            } compactLeading: {
                LAEnds(state: s, stale: stale) { e in LARing(state: s, ended: e, size: 22, onIsland: true, t: t) }
                    .overlay { Image(systemName: s.symbol).font(.system(size: 8, weight: .medium)) }
            } compactTrailing: {
                LAEnds(state: s, stale: stale) { e in LACompactTrailing(state: s, ended: e) }
            } minimal: {
                LAEnds(state: s, stale: stale) { e in LARing(state: s, ended: e, size: 22, onIsland: true, t: t) }
            }
        }
    }
}
#endif
