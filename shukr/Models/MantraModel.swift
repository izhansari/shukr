//
//  Mantra.swift
//  shukr
//
//  Created by Izhan S Ansari on 9/24/24.
//


import Foundation
import SwiftData

@Model
class MantraModel: Identifiable {
    var id: UUID
    var text: String

    init(text: String) {
        self.id = UUID()
        self.text = text
    }
}
