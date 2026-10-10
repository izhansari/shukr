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
        app.launchArguments += ["-demoPerfRun"]   // any -demo… skips welcome / prompts / setup; nothing else changes
        // Extra launch args from the run (xcodebuild … TEST_RUNNER_PERF_ARGS="-perf_x -perf_y").
        app.launchArguments += (ProcessInfo.processInfo.environment["PERF_ARGS"] ?? "").split(separator: " ").map(String.init)
        print("PERF launch args:", app.launchArguments.joined(separator: " "))
        app.launch()
        sleep(3)
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
}
