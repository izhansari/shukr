//
//  TasbeehModels.swift
//  shukr
//
//  The counting session's state (tasbeehView), in three @Observable objects — the clock, the count, the stage —
//  one per view, for the view's life, as its @State were (cleanup-map tangle 5, step 6). The view keeps every name as a
//  forwarding accessor, so its code reads as before; what each one means is documented there.
//

import SwiftUI
import SwiftData

@MainActor @Observable final class TasbeehClock {
    var timerIsActive: Bool = false
    var timerbb: Timer? = nil
    var paused: Bool = false
    var timeOffset: TimeInterval = 0
    var startTime: Date? = nil
    var endTime: Date? = nil
    var pauseStartTime: Date? = nil
    var secsPassedAtPause: TimeInterval = 0
    var progressFraction: CGFloat = 0
    var inactivityTimer: Timer? = nil
    var timeSinceLastInteraction: TimeInterval = 0
    var showInactivityAlert: Bool = false
    var countDownForAlert: Int = 0
    var stoppedDueToInactivity: Bool = false
    var totalPauseInSession: Double = 0
    var secsToReport: TimeInterval = 0
}
