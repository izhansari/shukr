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
        let library = shortcuts.buttons["Library"]
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
        openShukrPage()
        let tile = shortcuts.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", String(title.prefix(12)))).firstMatch
        if tile.waitForExistence(timeout: 3) { tile.tap(); sleep(5) }
        shot("tile-" + title)
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
