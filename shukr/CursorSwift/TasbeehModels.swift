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

@MainActor @Observable final class TasbeehStage {
    var entryFrom: CGRect? = SessionHandoff.shared.freshEntry?.frame
    var landingBase: Double? = SessionHandoff.shared.freshEntry?.landingBase
    var entryOffset: CGSize = .zero
    var pageIn: Bool = SessionHandoff.shared.freshEntry == nil && !SessionHandoff.shared.enteringInPlace
    var countIn: Bool = SessionHandoff.shared.freshEntry == nil && !SessionHandoff.shared.enteringInPlace
    var chromeIn: Bool = SessionHandoff.shared.freshEntry == nil && !SessionHandoff.shared.enteringInPlace
    var sequence: Task<Void, Never>? = nil
    var resultsTask: Task<Void, Never>? = nil
    var openingStyle: SessionOpening = .current
    var leaving: Bool = false
    var topBarHeight: CGFloat = 0
    var startFraction: CGFloat = 0
    var ringAtStop: CGFloat? = nil
    var ringHeld: Bool = false
    var arcSettled: Bool = false
    var ringOut: Bool = SessionHandoff.shared.enteringInPlace
    var resultsIn: Bool = false
    var ringSize: CGSize = .zero
    var ringHomeMid: CGPoint = .zero
    var cardsBottomTop: CGFloat = 0
    var ringLift: CGFloat = 0
    var ringMoveTask: Task<Void, Never>? = nil
    var sleepChipFrame: CGRect = .zero
    var pauseButtonFrame: CGRect = .zero
    var chipsFrame: CGRect = .zero
    var ringDimmed: Bool = false
    var cardsStay: Bool = false
    var ringToCentre: Bool = false
    var offsetY: CGFloat = 0
    var highestPoint: CGFloat = 0
    var lowestPoint: CGFloat = 0
    var dragToIncrementBool: Bool = true
    var sleptDark: Bool = false
    var resultsDimmed: Bool = false
    var appLookDark: Bool = false
}
