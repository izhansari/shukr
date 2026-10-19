//
//  shukrWidgetBundle.swift
//  shukrWidget
//
//  Created by Izhan S Ansari on 8/3/24.
//

import WidgetKit
import SwiftUI

@main
struct shukrWidgetBundle: WidgetBundle {
    var body: some Widget {
//        CompassWidget()
        PrayersWidget()
        ZikrTasksWidget()
        NameOfTheDayWidget()
        DailyAyahWidget()
        ShukrControls().body   // Prayer, Qibla, Tasbeeh, Daily Ayah, 99 Names, Memories (MoreWidgets.swift)
        PrayerWindowLiveActivity()   // each prayer window as a Live Activity (PrayerLiveActivities.swift)
    }
}

//@main
//struct CompassWidgetBundle: WidgetBundle {
//    var body: some Widget {
//    }
//}
