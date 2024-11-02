//
//  shukrApp.swift
//  shukr
//
//  Created on 8/3/24.
//

import SwiftUI
import SwiftData

@main
struct shukrApp: App {

    
    @StateObject var sharedState = SharedStateClass()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SessionDataModel.self,
            ClickDataModel.self, // Add all models here
            MantraModel.self,
            TaskModel.self,
            DuaModel.self,
            PrayerModel.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
//            tasbeehView()
            PrayerTimesView()
        }
        .modelContainer(sharedModelContainer)
        .environmentObject(sharedState) // Inject shared state into the environment (Global access point for `sharedState`)
        // Inject `sharedState` as an EnvironmentObject at the top level of the app.
        // This makes `sharedState` globally accessible to any view within the view hierarchy
        // that starts from `PrayerTimesView`.
        // All subviews can access it implicitly by declaring
        // `@EnvironmentObject var sharedState: SharedStateClass`.
        // NOTE: This injection covers all views in the hierarchy. Additional injections are unnecessary,
        // unless a view is presented outside this hierarchy, like with a new window or distinct view instance.
    }
}
