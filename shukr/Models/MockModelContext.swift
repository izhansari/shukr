//
//  MockModelContext.swift
//  shukr
//
//  Created by Izhan S Ansari on 9/25/24.
//


import SwiftData
import SwiftUI

class MockModelContext: ObservableObject {
    @Published var sessions: [SessionDataModel]
    @Published var mantras: [MantraModel]

    init(sessions: [SessionDataModel], mantras: [MantraModel]) {
        self.sessions = sessions
        self.mantras = mantras
    }
}
