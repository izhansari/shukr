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

@MainActor @Observable final class TasbeehCount {
    var sessionMantra: MantraModel? = nil
    var countingInSets: Bool = false
    var finishArmed: Bool = false
    var finishArmToken: Int = 0
    var tasbeeh: Int = 0
    var countOffset: Int = 0
    var autoStop: Bool = true
    var endedAsleep: Bool = false
    var newAvrgTPC: TimeInterval = 0
    var secsAtLastTap: TimeInterval = 0
    var lastTapAt: Date? = nil
    var sleptSaved: Bool = false
    var sleepResume: tasbeehView.SleepResume? = nil
    var resumeWanted: Bool = false
    var sleepResumeReady: Bool = false
    var stopCleanupPending: Bool = false
    var finishBuzzPlayed: Bool = false
    var savedSession: SessionDataModel? = nil
    var strokesThisTouch: Int = 0
    var postSalahPhase: Int = 0
    var tasbeehColorMode: Bool = false
    var goalFinishArmed: Bool = false
    var goalFinishToken: Int = 0
    var reminderVariant: Int = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments   // -reminderVariant N (screenshots)
        if let i = args.firstIndex(of: "-reminderVariant"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return Int.random(in: 0..<PostSalahReminder.count)
    }()
}
