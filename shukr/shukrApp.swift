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
//    var sharedModelContainer: ModelContainer = {
//        let schema = Schema([
//            Item.self,
//        ])
//        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//
//        do {
//            return try ModelContainer(for: schema, configurations: [modelConfiguration])
//        } catch {
//            fatalError("Could not create ModelContainer: \(error)")
//        }
//    }()
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SessionDataModel.self,
            ClickDataModel.self, // Add all models here
            MantraModel.self
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
            CombinedView()
            
//            VolumeTesting()
            
//                .preferredColorScheme(.light)
            
//            ContentView()
//                .preferredColorScheme(.light)
            
//            ShukrTimer()
//                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
//        .modelContainer(for: SessionDataModel.self)
        
    }
}
