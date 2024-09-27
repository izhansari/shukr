//
//  SessionModel.swift
//  shukr
//
//  Created on 9/21/24.
//
import Foundation
import SwiftData

@Model
class SessionDataModel: Identifiable {

    var id: String

    var title: String                   // (placeHolderTitle for now...)
    var sessionMode: Int                // selectedPage
    var targetMin: Int                  // selectedMin
    var targetCount: Int                // targetCount

    var totalCount: Int                 // tasbeeh
    
    var startTime: Date                 // startTime (prev sessionTime)
    var secondsPassed: TimeInterval     // ???
    var sessionDuration: String         // formatSecToMinAndSec(clickStats.last?.date.timeIntervalSince(startTime) ?? 0)
    var avgTimePerClick: TimeInterval   // avgTimePerClick

    var tasbeehRate: String             // tasbeehRate

    var clickStats: [ClickDataModel]    // Array of ClickDataModel
    // Use ClickDataModel instead of tuple -- he cant store custom tuples in persistence

    
    init(title: String, sessionMode: Int, targetMin: Int, targetCount: Int, totalCount: Int, startTime: Date, secondsPassed: TimeInterval, sessionDuration: String, avgTimePerClick: TimeInterval, tasbeehRate: String, clickStats: [ClickDataModel]) {
        self.id = UUID().uuidString
        self.title = title
        self.sessionMode = sessionMode
        self.targetMin = targetMin
        self.targetCount = targetCount
        self.totalCount = totalCount /* clickStats.count */
        self.startTime = startTime
        self.secondsPassed = secondsPassed /* clickStats.last?.date.timeIntervalSince(startTime)*/ 
        self.sessionDuration = sessionDuration
        self.avgTimePerClick = avgTimePerClick
        self.tasbeehRate = tasbeehRate
        self.clickStats = clickStats
    }
}
