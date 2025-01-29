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
        shukrWidget()
        shukrWidgetLiveActivity()
//        CompassWidget()
        PrayersWidget()
    }
}

//@main
//struct CompassWidgetBundle: WidgetBundle {
//    var body: some Widget {
//    }
//}
