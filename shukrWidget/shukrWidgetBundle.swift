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
//        shukrWidget()
//        CompassWidget()
        PrayersWidget()
        ZikrTasksWidget()
        NameOfTheDayWidget()
        DailyAyahWidget()
        QiblaControl()
        TasbeehControl()
        #if DEBUG
        LATestLiveActivity()   // Live Activity research (MY4R)
        #endif
    }
}

//@main
//struct CompassWidgetBundle: WidgetBundle {
//    var body: some Widget {
//    }
//}
