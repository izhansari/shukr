//
//  WidgetOpens.swift
//  shukr
//
//  The Salah page's widget / control / shortcut opens: the flags they leave, the page they open, and the Prayers
//  widget's "Unmark Asr?" prompt. An extension of PrayerTimesView, moved out of PrayerTimesAndTracker.swift
//  (cleanup-map tangle 1, step 2).
//

import SwiftUI
import SwiftData
import WidgetKit

extension PrayerTimesView {
    func openFromWidgetFlags() {
        guard !FirstRunSetup.isShowing else { return }
        if let store = UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget") {
            let openCompassFromWidget   = store.bool(forKey: "widgetCompass")
            let openTasbeehFromWidget   = store.bool(forKey: "widgetTasbeeh")
            if FirstRunSetup.deepLinkFlags.contains(where: { store.object(forKey: $0) != nil && store.bool(forKey: $0) })
                || store.string(forKey: "widgetZikrTask") != nil {
                lastDeepLinkAt = Uptime.now   // no reminders card over where a widget just sent you
            }
            // Clear only when set: every write to the group suite invalidates every
            // @AppStorage bound to it and re-renders Settings.
            // Excused, and the widget or Control Center tried to mark a prayer: ask whether she's back (Excused.swift).
            if store.bool(forKey: ExcusedResume.askKey) {
                store.set(false, forKey: ExcusedResume.askKey)
                if Excused.isActive { resumePrayer = nil; askingResume = true }
            }
            if openCompassFromWidget { store.setValue(false, forKey: "widgetCompass") }
            if openTasbeehFromWidget { store.setValue(false, forKey: "widgetTasbeeh") }
            let openAyahFromWidget  = store.bool(forKey: "widgetDailyAyah")
            let openNamesFromWidget = store.bool(forKey: "widgetNames")
            if openAyahFromWidget { store.setValue(false, forKey: "widgetDailyAyah") }
            if openNamesFromWidget { store.setValue(false, forKey: "widgetNames") }
            // "Find Nearby Mosques" (Shortcuts / Siri): the map, on its mosques.
            let openMosques = store.bool(forKey: FindNearbyMosquesIntent.flag)
            if openMosques { store.set(false, forKey: FindNearbyMosquesIntent.flag) }
            // Prayed Here's "See your prayers on the map": the map on its prayer spots.
            let openSpots = store.bool(forKey: OpenPrayerSpotsIntent.flag)
            if openSpots { store.set(false, forKey: OpenPrayerSpotsIntent.flag) }
            // Whatever is covering the page (the map, a pushed page) goes first, or the
            // widget's page opened behind it (owner, 2026-09-26).
            let zikrTaskID = store.string(forKey: "widgetZikrTask")
            if zikrTaskID != nil { store.removeObject(forKey: "widgetZikrTask") }
            // A Live Activity's Tasbih: Tasbih Fatimah, as the post-salah pill opens it.
            if store.bool(forKey: PrayerLiveActivities.openTasbihKey) {
                store.set(false, forKey: PrayerLiveActivities.openTasbihKey)
                lastDeepLinkAt = Uptime.now
                clearCovers {
                    sharedState.horizontalPage = .main
                    sharedState.isDoingPostNamazZikr = true
                    showTasbeehPage = true
                }
            }
            
            // The Memories control / shortcut: its full-screen page over the Salah page.
            if store.bool(forKey: "widgetMemories") {
                store.set(false, forKey: "widgetMemories")
                lastDeepLinkAt = Uptime.now
                clearCovers {
                    sharedState.go(to: .main, animated: false)
                    MemoriesPresenter.shared.open = true
                }
            }

            // The Today's Prayers control: the Salah page with today's list up.
            if store.bool(forKey: OpenPrayerListIntent.flag) {
                store.set(false, forKey: OpenPrayerListIntent.flag)
                lastDeepLinkAt = Uptime.now
                clearCovers {
                    sharedState.horizontalPage = .main
                    sharedState.navPosition = .bottom
                }
            }

            // A task tapped in the Zikr Tasks card: the Zikr page's wheel starts it, today's count carried on.
            if store.bool(forKey: StartZikrTaskIntent.flag) {
                store.set(false, forKey: StartZikrTaskIntent.flag)
                if let id = store.string(forKey: StartZikrTaskIntent.idKey) {
                    store.removeObject(forKey: StartZikrTaskIntent.idKey)
                    lastDeepLinkAt = Uptime.now
                    openFromWidget {
                        // A turn later, as the Zikr widget's open: on a cold launch the pager isn't laid out yet and
                        // its first report put it back on Salah. Started once the page is there.
                        DispatchQueue.main.async {
                            sharedState.go(to: .zikr, animated: false)
                            Task { @MainActor in
                                _ = await CircleStage.shared.until(deadline: 1.5) { CircleStage.shared.restingPage == .zikr }
                                ZikrFocus.start(id, resume: true)
                            }
                        }
                    }
                }
            }

            // The Fajr alarm's "I'm up — open Fajr" (AlarmKit): the Salah page, nothing over it.
            if store.bool(forKey: "alarmOpenSalah") {
                store.set(false, forKey: "alarmOpenSalah")
                lastDeepLinkAt = Uptime.now
                clearCovers { sharedState.horizontalPage = .main }
            }
            // A marked row in the widget's times list: ask here, never unmark there.
            if store.string(forKey: WidgetListMarks.unmarkKey) != nil {
                lastDeepLinkAt = Uptime.now
                widgetUnmarkToken += 1
                showWidgetUnmarkWhenClear(token: widgetUnmarkToken)
            }
            // A prayer marked from the widget's list, possibly on another prayer day than the app's
            // (a list drawn before Fajr, tapped after): that day's score and the streaks.
            if store.object(forKey: WidgetListMarks.markedDayKey) != nil {
                let day = Date(timeIntervalSince1970: store.double(forKey: WidgetListMarks.markedDayKey))
                store.removeObject(forKey: WidgetListMarks.markedDayKey)
                viewModel.reconcileAfterWidgetWrites()
                viewModel.calculateDayScore(for: day)
                viewModel.recomputeStreaks()
            }
            // Every widget open goes straight there: no page slide, no push, no wheel turn (owner: "no animation go
            // straight to the desired task … any widget action honestly"; the welcome is skipped too — WelcomeGate).
            if openAyahFromWidget {
                openFromWidget {
                    sharedState.go(to: .main, animated: false)
                    instantly { showDailyAyahPage = true }
                }
            } else if openNamesFromWidget {
                openFromWidget {
                    sharedState.go(to: .main, animated: false)
                    instantly { showNamesPage = true }
                }
            }

            if openMosques || openSpots || openCompassFromWidget {
                if showQiblaMap {
                    // Already open (on another layer, say): switch it — "Open qibla" left it on the mosques (review).
                    MapOpenRequest.layer = openMosques ? .mosques : openSpots ? .prayers : .qibla
                    NotificationCenter.default.post(name: MapOpenRequest.changed, object: nil)
                } else {
                    openFromWidget {
                        // Set only once it really opens (an open skipped under a tasbeeh session left it waiting for the
                        // next time the map was opened by hand — review). The qibla is the map's own first layer.
                        MapOpenRequest.layer = openMosques ? .mosques : openSpots ? .prayers : nil
                        instantly {
                            sharedState.navPosition = .main
                            showQiblaMap = true
                        }
                    }
                }
            }
            
            else if openTasbeehFromWidget{
                openFromWidget {
                    // A task row in the Zikr widget: that task's circle already in the middle.
                    if let zikrTaskID { ZikrFocus.request(zikrTaskID, instant: true) }
                    // A turn later: on a cold launch the pager isn't laid out yet, and its first report put it back on
                    // Salah.
                    DispatchQueue.main.async { sharedState.go(to: .zikr, animated: false) }
                }
            }
        }
    }

    /// A widget open: at once when nothing covers the page (a cold launch — no hop through a task, so the page is
    /// already there when the app first shows), else once the covers have gone (`clearCovers`).
    private func openFromWidget(_ go: @escaping @MainActor () -> Void) {
        guard !showTasbeehPage else { return }
        if !somethingCovers && CircleCover.active.isEmpty {
            pendingOpen?.cancel()
            go()
        } else {
            clearCovers { go() }
        }
    }

    /// A change with no animation (a widget open: the page is simply there). The root stack's push is UIKit's and
    /// ignores the transaction, so UIKit's animations are off too for a moment.
    private func instantly(_ change: () -> Void) {
        UIView.setAnimationsEnabled(false)
        var quiet = Transaction(); quiet.disablesAnimations = true
        withTransaction(quiet, change)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UIView.setAnimationsEnabled(true) }
    }

    /// "Unmark Asr?" → Unmark, from the widget's times list: today's row goes through the app's own
    /// unmark (as the list's own alert does: day score, streak, widget); a row of another day has
    /// every completed row of it reset, then the day and streaks are redone.
    private func unmarkFromWidget(_ request: WidgetUnmarkRequest) {
        viewModel.reconcileAfterWidgetWrites()   // a widget mark that just landed
        // Every completed row of that prayer on that day (a day can hold duplicates): the one on
        // today's list through the app's own unmark (haptic, day score, streak, widget), the rest reset.
        let shown = viewModel.todaysPrayers.first {
            !TourRuntime.isPracticeAnywhere($0) && $0.isCompleted && $0.name == request.name && Calendar.current.isDate($0.startTime, inSameDayAs: request.start)
        }
        let others = completedRows(request).filter { $0.persistentModelID != shown?.persistentModelID }
        others.forEach { $0.resetPrayer(); PrayerPhotos.discard(for: $0) }
        if !others.isEmpty { DayHistory.invalidate() }   // another day's prayer: the day page's history (mark audit #5)
        if let shown {
            viewModel.togglePrayerCompletion(for: shown)   // rescores the day and the streak, pushes the widget
        } else if !others.isEmpty {
            viewModel.calculateDayScore(for: PrayerDay.start(forRow: request.name, startingAt: request.start))
            viewModel.recomputeStreaks()
            viewModel.pushCompletionsToWidget()
        }
    }

    /// The completed rows of the request's prayer on its calendar day.
    private func completedRows(_ request: WidgetUnmarkRequest) -> [PrayerModel] {
        let name = request.name
        // 2.8.0: the prayer day the request's start falls in, by key.
        let rows = (try? context.fetch(FetchDescriptor<PrayerModel>(
            predicate: PrayerDay.rowsPredicate(forRow: name, startingAt: request.start)))) ?? []
        return rows.filter { $0.name == name && $0.isCompleted }
    }

    /// "Unmark Asr?" appears over whatever is on screen — the Zikr page, Settings, a pushed page, the
    /// map, a sheet or the ☰ popover — with no navigating (owner, CBBBBD1D: it only came up on the Salah
    /// page). It's a UIKit alert in its own window above the app (`OverlayAlert`), so no sheet, popover
    /// or cover can hide it (presented from the root it sat under a sheet SwiftUI had presented from a
    /// nested controller). It waits during the first-run setup and the opening and while the app isn't active; a
    /// tasbeeh session is paused first. Until then the request stays in the app group; the next activation picks it
    /// up again.
    func showWidgetUnmarkWhenClear(token: Int) {
        unmarkWait?.cancel()
        unmarkWait = Task { await showWidgetUnmark(token: token) }
    }

    /// Waits on the stage — the app active, no setup, no welcome — waking when that changes (it retried every second,
    /// 90 times: tr-final); the request stays in the app group meanwhile, and the next activation tries again.
    private func showWidgetUnmark(token: Int) async {
        let stage = CircleStage.shared
        let welcome = WelcomeTarget.state
        guard token == widgetUnmarkToken, widgetUnmark == nil,
              let store = UserDefaults(suiteName: SharedStore.appGroup),
              store.string(forKey: WidgetListMarks.unmarkKey) != nil,
              await stage.until(deadline: Self.unmarkDeadline, {
                  // …and not during the tour: its list is the practice day (Ben's G7).
                  stage.sceneActive && !welcome.playing && !stage.covers.contains("firstRunSetup")
                      && !TourRuntime.shared.active
              }),
              token == widgetUnmarkToken, OverlayAlert.canShow else { return }
        // A tasbeeh session up: it goes into its pause state first, then the prompt shows over it (owner,
        // CA197AE2 — it used to wait until the session closed). `CircleCover` "tasbeeh" is set by the session
        // itself: this closure's own view copy can read a stale `showTasbeehPage`.
        if showTasbeehPage || stage.covers.contains("tasbeeh") {
            NotificationCenter.default.post(name: TasbeehSession.pauseRequest, object: nil)
            guard await CircleGate.pause(Self.sessionPausesDuration), token == widgetUnmarkToken else { return }
        }
        guard let raw = store.string(forKey: WidgetListMarks.unmarkKey) else { return }
        guard let request = WidgetUnmarkRequest(raw) else { store.removeObject(forKey: WidgetListMarks.unmarkKey); return }
        // Still wanted (not already unmarked meanwhile): show it, and only then take the request.
        store.removeObject(forKey: WidgetListMarks.unmarkKey)
        let rows = completedRows(request)
        guard !rows.isEmpty else { return }
        var shown = request
        shown.displayName = rows.contains(where: \.isJumuah) ? "Jumu'ah" : request.name
        widgetUnmark = shown
        // The app's unmark card (UnmarkPrompt; with the photo when one goes with the mark).
        if UnmarkPrompt.ask(for: rows[0], title: shown.displayName,
                            photoFrom: rows.first(where: PrayerPhotos.exists(for:)),
                            onCancel: { widgetUnmark = nil },
                            onUnmark: { widgetUnmark = nil; unmarkFromWidget(shown) }) {
            return
        }
        let alert = UIAlertController(title: "Unmark \(shown.displayName)?",
                                      message: "Are you sure you want to mark this prayer as incomplete?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            widgetUnmark = nil
            OverlayAlert.finish()
        })
        alert.addAction(UIAlertAction(title: "Unmark", style: .destructive) { _ in
            widgetUnmark = nil
            OverlayAlert.finish()
            unmarkFromWidget(shown)
        })
        OverlayAlert.show(alert)
    }
}

/// A marked row tapped in the Prayers widget's times list: which prayer, on which day
/// (`WidgetListMarks.unmarkKey`, "Asr|<start, seconds since 1970>").
struct WidgetUnmarkRequest: Identifiable {
    let name: String
    let start: Date
    /// What the alert calls it: "Jumu'ah" for a Friday Dhuhr prayed at a masjid.
    var displayName: String
    var id: String { "\(name)|\(start.timeIntervalSince1970)" }

    init?(_ raw: String) {
        let parts = raw.split(separator: "|")
        guard parts.count == 2, let seconds = Double(parts[1]) else { return nil }
        name = String(parts[0])
        start = Date(timeIntervalSince1970: seconds)
        displayName = name
    }
}
