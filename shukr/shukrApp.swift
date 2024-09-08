//
//  shukrApp.swift
//  shukr
//
//  Created by Izhan S Ansari on 8/3/24.
//

import SwiftUI
import SwiftData

@main
struct shukrApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
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
//                .preferredColorScheme(.light)
            
//            ContentView()
//                .preferredColorScheme(.light)
            
//            ShukrTimer()
//                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
        
    }
}
