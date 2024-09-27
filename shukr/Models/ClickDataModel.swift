//
//  ClickDataModel.swift
//  shukr
//
//  Created on 9/24/24.
//

import Foundation
import SwiftData

@Model
class ClickDataModel {
    var id: UUID
    var date: Date
    var pauseTime: TimeInterval
    var tpc: TimeInterval
    
    init(date: Date, pauseTime: TimeInterval, tpc: TimeInterval) {
        self.id = UUID() // Generate a unique ID for each ClickData entry
        self.date = date
        self.pauseTime = pauseTime
        self.tpc = tpc
    }
}
