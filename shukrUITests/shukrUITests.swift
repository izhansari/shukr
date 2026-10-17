//
//  shukrUITests.swift
//  shukrUITests
//
//  Created by Izhan S Ansari on 8/3/24.
//

import XCTest

final class shukrUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    // MARK: Paging smoothness (scheme shukrPerf, Release). Hitches = frames the app delivered late while paging.
    // Run on a phone: xcodebuild test -scheme shukrPerf -destination id=<udid> -only-testing:shukrUITests/shukrUITests/testPagingHitches

    private func launchForPerf() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-demoPerfRun", "-perfFrames"]   // any -demo… skips welcome / prompts / setup; nothing else changes
        // Extra launch args from the run (xcodebuild … TEST_RUNNER_PERF_ARGS="-perf_x -perf_y").
        app.launchArguments += (ProcessInfo.processInfo.environment["PERF_ARGS"] ?? "").split(separator: " ").map(String.init)
        print("PERF launch args:", app.launchArguments.joined(separator: " "))
        app.launch()
        sleep(UInt32(ProcessInfo.processInfo.environment["PERF_DELAY"] ?? "") ?? 3)   // time to start a recorder
        return app
    }

    private func perfOptions() -> XCTMeasureOptions {
        let o = XCTMeasureOptions()
        o.iterationCount = 5
        return o
    }

    /// Salah → Zikr → Salah → Settings → Salah, the owner's left / right swipes.
    @available(iOS 26.0, *)
    func testPagingHitches() throws {
        let app = launchForPerf()
        let window = app.windows.firstMatch
        measure(metrics: [XCTHitchMetric(application: app), XCTOSSignpostMetric.scrollingAndDecelerationMetric],
                options: perfOptions()) {
            window.swipeLeft(velocity: .default)
            usleep(700_000)
            window.swipeRight(velocity: .default)
            usleep(700_000)
            window.swipeRight(velocity: .default)
            usleep(700_000)
            window.swipeLeft(velocity: .default)
            usleep(700_000)
        }
    }

    /// Explore shukr, scrolled down its sections and back (run with PERF_ARGS="-perfExplore" on a PERFARGS build: the page
    /// opens over Salah). Its pictures are whole phones drawn and scaled (perf-recheck, 2026-10-14).
    @available(iOS 26.0, *)
    func testExploreScrollHitches() throws {
        let app = launchForPerf()
        let window = app.windows.firstMatch
        measure(metrics: [XCTHitchMetric(application: app)], options: perfOptions()) {
            window.swipeUp(velocity: .default)
            usleep(800_000)
            window.swipeUp(velocity: .default)
            usleep(800_000)
            window.swipeDown(velocity: .default)
            usleep(800_000)
            window.swipeDown(velocity: .default)
            usleep(800_000)
        }
    }

    /// A section's pictures paged sideways (PERF_ARGS="-perfExplore -demoExploreGroup lockWidgets -demoExploreMember
    /// lockTime": the Lock Screen widgets, each a whole phone).
    @available(iOS 26.0, *)
    func testExplorePagerHitches() throws {
        let app = launchForPerf()
        let window = app.windows.firstMatch
        func page(_ left: Bool) {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.85 : 0.15, dy: 0.28))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.15 : 0.85, dy: 0.28))
            from.press(forDuration: 0.02, thenDragTo: to, withVelocity: .default, thenHoldForDuration: 0)
            usleep(700_000)
        }
        measure(metrics: [XCTHitchMetric(application: app)], options: perfOptions()) {
            page(true); page(true); page(false); page(false)
        }
    }

    /// The Salah page's swipe up (list) and back down.
    @available(iOS 26.0, *)
    func testSalahVerticalHitches() throws {
        let app = launchForPerf()
        let window = app.windows.firstMatch
        measure(metrics: [XCTHitchMetric(application: app)], options: perfOptions()) {
            window.swipeUp(velocity: .default)
            usleep(900_000)
            window.swipeDown(velocity: .default)
            usleep(900_000)
        }
    }

    /// A drag up that drifts sideways on Salah: the list opens and the page stays (the per-drag pager lock). Read the
    /// result in the app's frames.log (pager lines carry the page).
    @available(iOS 26.0, *)
    func testSalahDiagonalStaysPut() throws {
        let app = launchForPerf()
        let window = app.windows.firstMatch
        for _ in 0..<3 {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)),
                        withVelocity: .default, thenHoldForDuration: 0)
            usleep(900_000)
            let back = window.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.35))
            back.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7)),
                       withVelocity: .default, thenHoldForDuration: 0)
            usleep(900_000)
        }
    }

    /// The same swipes with no metrics, for an Instruments recording alongside (XCTest's hitch metrics take the phone's
    /// one trace session: a recording started with them stopped after about a second).
    func testSalahVerticalSwipesOnly() throws {
        let window = launchForPerf().windows.firstMatch
        for _ in 0..<5 {
            window.swipeUp(velocity: .default)
            usleep(900_000)
            window.swipeDown(velocity: .default)
            usleep(900_000)
        }
    }

    func testPagingSwipesOnly() throws {
        let window = launchForPerf().windows.firstMatch
        for _ in 0..<5 {
            window.swipeLeft(velocity: .default); usleep(700_000)
            window.swipeRight(velocity: .default); usleep(700_000)
            window.swipeRight(velocity: .default); usleep(700_000)
            window.swipeLeft(velocity: .default); usleep(700_000)
        }
    }

    /// Memories (opened by -perfOpenMemories): scroll Days, switch to Months and Prayers and back, open a pile, swipe
    /// through it, close it. Late frames land in the app's frames.log with the level / pile changes.
    @available(iOS 26.0, *)
    func testMemoriesHitches() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-demoPerfRun", "-perfFrames", "-perfOpenMemories"]
        app.launch()
        sleep(6)
        let window = app.windows.firstMatch
        measure(metrics: [XCTHitchMetric(application: app)], options: perfOptions()) {
            window.swipeDown(velocity: .default); usleep(800_000)
            window.swipeUp(velocity: .default); usleep(800_000)
            for level in ["Months", "Prayers", "Days"] {
                let b = app.buttons[level].firstMatch
                if b.exists { b.tap(); usleep(900_000) }
                window.swipeDown(velocity: .default); usleep(700_000)
                window.swipeUp(velocity: .default); usleep(700_000)
            }
            let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Fajr' OR label CONTAINS[c] 'Dhuhr' OR label CONTAINS[c] 'Asr' OR label CONTAINS[c] 'Maghrib' OR label CONTAINS[c] 'Isha'")).firstMatch
            if photo.exists {
                photo.tap(); usleep(1_200_000)
                for _ in 0..<3 { window.swipeLeft(velocity: .default); usleep(700_000) }
                for _ in 0..<3 { window.swipeRight(velocity: .default); usleep(700_000) }
                let close = app.buttons["Close"].firstMatch
                if close.exists { close.tap() } else { window.swipeDown(velocity: .default) }
                usleep(1_200_000)
            }
        }
    }

    // MARK: Journey (journey-perf, 2026-10-15): opened the way he does — ☰ → Journey — on his real data (never the seed).

    private func openJourney(_ app: XCUIApplication) {
        let menu = app.buttons.matching(NSPredicate(format: "label IN {'Menu', 'More', 'line.3.horizontal'} OR identifier == 'line.3.horizontal'")).firstMatch
        if menu.waitForExistence(timeout: 4) { menu.tap() } else { app.windows.firstMatch.swipeDown(velocity: .slow) }
        let row = app.buttons["Journey"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 4), "no Journey row in ☰")
        row.tap()
        XCTAssertTrue(app.staticTexts["Journey"].firstMatch.waitForExistence(timeout: 4), "Journey didn't open")
        sleep(2)
    }

    /// One pass through Journey: months back and forth, Calendar ⇄ Grid, the page scrolled, a day opened and scrolled, back.
    private func journeyPass(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        for label in ["Previous month", "Previous month", "Next month", "Next month"] {
            let b = app.buttons[label].firstMatch
            if b.exists && b.isEnabled { b.tap(); usleep(700_000) }
        }
        for label in ["Grid", "Calendar"] {
            let b = app.buttons[label].firstMatch
            if b.exists { b.tap(); usleep(900_000) }
            window.swipeUp(velocity: .default); usleep(800_000)
            window.swipeDown(velocity: .default); usleep(800_000)
        }
        let day = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS ' of 5 prayed'")).firstMatch
        if day.exists {
            day.tap(); usleep(1_500_000)
            window.swipeUp(velocity: .default); usleep(800_000)
            window.swipeDown(velocity: .default); usleep(800_000)
            let back = app.navigationBars.buttons.firstMatch
            if back.exists { back.tap() } else {
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
            }
            usleep(1_200_000)
        }
    }

    @available(iOS 26.0, *)
    func testJourneyHitches() throws {
        let app = launchForPerf()
        openJourney(app)
        measure(metrics: [XCTHitchMetric(application: app)], options: perfOptions()) { journeyPass(app) }
    }

    // MARK: Journey on one screen + the calendar (2026-10-16, build-plan.md): the card's weeks, a tile, a month name → the
    // month, months up and down, the title → the year, the year scrolled, a small month, back. Run on Laraib's 15 Pro.

    private func back(_ app: XCUIApplication) {
        let b = app.navigationBars.buttons.firstMatch
        if b.exists { b.tap() } else {
            let w = app.windows.firstMatch
            w.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
        }
        usleep(1_200_000)
    }

    /// Drags inside an element, by a fraction of its height (positive: down).
    private func drag(_ e: XCUIElement, _ by: CGFloat) {
        let from = e.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: by > 0 ? 0.25 : 0.75))
        from.press(forDuration: 0.02, thenDragTo: e.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: (by > 0 ? 0.25 : 0.75) + by)),
                   withVelocity: .default, thenHoldForDuration: 0)
        usleep(800_000)
    }

    /// On screen: its centre inside the area (the card, or the window) up and down. Not isHittable — that throws on a tile scrolled out of the card ("Failed
    /// to determine hittability of "Friday, April 4"", his 13 Pro Max, 2026-10-16).
    private func inView(_ e: XCUIElement, _ area: XCUIElement) -> Bool {
        guard e.exists, area.exists else { return false }
        let f = e.frame
        let a = area.frame.insetBy(dx: 0, dy: 8)          // up and down only: the month names sit beside the card's grid
        return !f.isEmpty && f.midY > a.minY && f.midY < a.maxY
    }

    private func calendarPass(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        let weeks = app.otherElements["Your weeks, a week a row"].firstMatch
        if weeks.exists { drag(weeks, 0.5); drag(weeks, -0.5) }                       // the card's weeks, back and forth
        let tile = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Friday'")).allElementsBoundByIndex
            .filter { inView($0, weeks) }.last                                // a Friday in view (the latest)
        if let tile { tile.tap(); usleep(700_000); tile.tap(); usleep(700_000) }       // a tile's line, then the numbers
        // the latest month name in view (the card shows today's weeks; older names sit scrolled away)
        let month = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open '")).allElementsBoundByIndex
            .filter { inView($0, weeks) }.max { $0.frame.minY < $1.frame.minY }
        guard let month else { return }
        month.tap(); usleep(1_400_000)                                                 // a month name → the month
        for by in [0.35, 0.35, -0.35, -0.35] as [CGFloat] { drag(window, by) }         // months up and down
        let title = app.buttons.matching(NSPredicate(format: "label MATCHES '^[A-Z][a-z]+ [0-9]{4}$'")).firstMatch
        if title.exists { title.tap(); usleep(1_200_000) }                             // the title → the year
        window.swipeDown(velocity: .default); usleep(900_000)                          // earlier years
        window.swipeUp(velocity: .default); usleep(900_000)
        let small = app.buttons.matching(NSPredicate(format: "label CONTAINS ' days · '")).allElementsBoundByIndex
            .filter { inView($0, window) }.last
        if let small { small.tap(); usleep(1_200_000) }                                // a small month → that month
        back(app)                                                                      // back to Journey
    }

    @available(iOS 26.0, *)
    func testJourneyCalendarHitches() throws {
        let app = launchForPerf()
        openJourney(app)
        measure(metrics: [XCTHitchMetric(application: app), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)],
                options: perfOptions()) { calendarPass(app) }
    }

    /// The same moves with no metrics, for an Instruments recording (or frames.log) alongside.
    func testJourneyCalendarSwipesOnly() throws {
        let app = launchForPerf()
        openJourney(app)
        for _ in 0..<3 { calendarPass(app) }
    }

    /// The same moves with no metrics (an Instruments recording alongside), then JOURNEY_IDLE seconds still on Journey.
    func testJourneySwipesOnly() throws {
        let app = launchForPerf()
        openJourney(app)
        for _ in 0..<3 { journeyPass(app) }
        sleep(UInt32(ProcessInfo.processInfo.environment["JOURNEY_IDLE"] ?? "") ?? 0)
    }
}

/// Live Activity research (MY4R, 2026-10-11): drives a real phone with a Dynamic Island through a test chain and keeps
/// screenshots (compact, expanded, Mark prayed, the Lock Screen look in Notification Center). The app logs the rest to
/// the app group's Library/Caches/la-test.log.
final class LiveActivityUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
    private func tree(_ name: String) {
        let a = XCTAttachment(string: springboard.debugDescription)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
    private func expandIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        sleep(2)
    }
    private func collapse() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        sleep(1)
    }


    /// The island and the card for one window live now: a long one, then one in its last half hour, then marked.
    func testIslandLook() throws {
        for (i, ago) in ["30", "125"].enumerated() {
            let app = XCUIApplication()
            app.launchArguments = ["-laEndAll", "-laNowAgo", ago, "-laLength", "150"]
            app.launch()
            sleep(4)
            XCUIDevice.shared.press(.home)
            sleep(3)
            if springboard.buttons["Allow"].waitForExistence(timeout: 2) { springboard.buttons["Allow"].tap(); sleep(2) }   // the simulator's own prompt
            shot("\(i) a compact")
            expandIsland()
            shot("\(i) b expanded")
            collapse()
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
                .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7)))
            sleep(2)
            if springboard.buttons["Allow"].exists { springboard.buttons["Allow"].tap(); sleep(2) }
            shot("\(i) c card")
            XCUIDevice.shared.press(.home)
            sleep(1)
        }
        expandIsland()
        let mark = springboard.buttons["Mark prayed"]
        if mark.waitForExistence(timeout: 3) {
            mark.tap()
            sleep(3)
            expandIsland()
            shot("2 b marked expanded")
        }
    }


}

/// shukr's Shortcuts tiles and Siri phrases on a real phone (a simulator build can't run App Shortcuts: unsigned).
/// Never runs "I Prayed" — it would mark a real prayer. Screenshots are kept in the result bundle.
final class ShortcutsOnDeviceTests: XCTestCase {
    private let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func tree(_ name: String) {
        let a = XCTAttachment(string: shortcuts.debugDescription)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The shukr page in the Shortcuts app's Library.
    private func openShukrPage() {
        shortcuts.terminate()
        shortcuts.launch()
        sleep(3)
        // A fresh Shortcuts (a new iOS) opens on its What's New first.
        let next = shortcuts.buttons["Continue"].firstMatch
        if next.exists { next.tap(); sleep(2) }
        let library = shortcuts.buttons["Library"].firstMatch
        if library.exists { library.tap(); sleep(1) }
        // Back to the top of the Library.
        for _ in 0..<3 where shortcuts.navigationBars.buttons.firstMatch.exists && !shortcuts.staticTexts["All Shortcuts"].exists {
            shortcuts.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        // The Library lists apps as buttons, built as they scroll in; shukr is near the end.
        let row = shortcuts.buttons["shukr"].firstMatch
        for _ in 0..<14 where !(row.exists && row.isHittable) { shortcuts.swipeUp(velocity: .fast) }
        if row.exists { row.tap(); sleep(2) }
    }

    /// One tile, named by `SHORTCUT_TILE` (default Today's Times), then Siri with `SHORTCUT_PHRASE` if set.
    func testOneTile() throws {
        let env = ProcessInfo.processInfo.environment
        let title = env["SHORTCUT_TILE"] ?? "Today's Times"
        // SHORTCUT_WARM: shukr already running (unlocked Zikr page) before the tile runs.
        if env["SHORTCUT_WARM"] != nil {
            let app = XCUIApplication(bundleIdentifier: "com.betternorms.shukr")
            app.launchArguments = ["-zikrUnlocked"] + (env["SHORTCUT_ARGS"]?.split(separator: " ").map(String.init) ?? [])
            app.launch(); sleep(4)
            XCUIDevice.shared.press(.home); sleep(1)
        }
        openShukrPage()
        shot("page")
        for _ in 0..<3 { shortcuts.swipeDown() }   // the tiles sit above the grouped choices
        let tile = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", String(title.prefix(12)))).firstMatch
        for _ in 0..<5 where !(tile.exists && tile.isHittable) { shortcuts.swipeUp() }
        if tile.exists { tile.tap(); sleep(UInt32(env["SHORTCUT_WAIT"].flatMap { UInt32($0) } ?? 5)) } else {
            tree("tree-" + title)
            // Not on the page: the Shortcuts app's own search finds the action.
            let search = shortcuts.searchFields.firstMatch
            if search.waitForExistence(timeout: 2) {
                search.tap(); search.typeText(title); sleep(3)
                shot("search-" + title)
                let hit = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).element(boundBy: 1)
                if hit.exists { hit.tap(); sleep(6) }
            }
        }
        shot("tile-" + title)
        // SHORTCUT_TAP: a button in the card by its label (a row's "Start …"), then what comes up.
        if let label = env["SHORTCUT_TAP"] {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let pred = NSPredicate(format: "label == %@", label)
            let inApp = shortcuts.descendants(matching: .any).matching(pred).firstMatch
            let target = inApp.exists ? inApp : springboard.descendants(matching: .any).matching(pred).firstMatch
            // SHORTCUT_TAP_AT "x,y" (points): a snippet's buttons report card-local frames, so they aren't hittable by query.
            if let at = env["SHORTCUT_TAP_AT"]?.split(separator: ",").compactMap({ Double($0) }), at.count == 2 {
                springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: at[0], dy: at[1])).tap()
            } else if target.exists { target.tap() } else { tree("no-" + label) }
            sleep(5)
            shot("tapped-" + label)
            let done = shortcuts.buttons["Done"].firstMatch
            if done.exists { done.tap() }
            sleep(2)
            shot("after-done-" + label)
        }
        if let phrase = env["SHORTCUT_PHRASE"] {
            XCUIDevice.shared.press(.home); sleep(1)
            XCUIDevice.shared.siriService.activate(voiceRecognitionText: phrase)
            sleep(7)
            shot("siri-" + phrase)
        }
        XCUIDevice.shared.press(.home)
    }

    func testTilesAndSiri() throws {
        continueAfterFailure = true
        openShukrPage()
        shot("01-shukr-page")
        tree("01-tree")

        // Each tile but I Prayed: run it, keep what it shows.
        for (i, title) in ["Prayer Time", "Time Left", "Today's Times", "Fajr Alarm Time", "Open Nearby Mosques",
                           "Open shukr", "Open Tasbih Fatimah"].enumerated() {
            openShukrPage()
            let tile = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", String(title.prefix(12)))).firstMatch
            guard tile.waitForExistence(timeout: 3) else { shot(String(format: "%02d-missing-%@", i + 10, title)); continue }
            tile.tap()
            sleep(5)
            shot(String(format: "%02d-%@", i + 10, title))
        }

        // Siri, typed in.
        // "Open qibla" right after "Nearby mosques": the open map must switch back to the qibla.
        for (i, phrase) in ["Fajr time in shukr", "Next prayer in shukr", "How long is left in shukr", "Today's prayer times in shukr",
                            "15 minutes before Maghrib in shukr", "Nearby mosques in shukr", "Open qibla in shukr",
                            "Open memories in shukr"].enumerated() {
            XCUIDevice.shared.press(.home)
            sleep(1)
            XCUIDevice.shared.siriService.activate(voiceRecognitionText: phrase)
            sleep(7)
            shot(String(format: "%02d-siri-%@", i + 30, phrase))
        }
        XCUIDevice.shared.press(.home)
    }
}
