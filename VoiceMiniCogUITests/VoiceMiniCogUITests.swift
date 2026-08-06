//
//  VoiceMiniCogUITests.swift
//  VoiceMiniCogUITests
//
//  Created by Azam Tolla on 3/12/26.
//

import XCTest

final class VoiceMiniCogUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// Task 6 voice-mode smoke: with no Tavus key the app must resolve to the
    /// voice guide (no "Retry Connection" dead-end), the welcome phase must
    /// unlock Begin Assessment, and orientation must ADVANCE past its first
    /// question — the Task 6 blocker fix in action: the QAPhaseView voice-mode
    /// ASR window + speech fixture posts .patientStartedSpeaking /
    /// .patientDoneSpeaking, without which every question sits out its 10 s
    /// timeout. `-speechFixtures YES` injects a simulated utterance 1.5 s
    /// after each listening window opens (simulator has no microphone).
    @MainActor
    func testVoiceModeSessionReachesOrientationAndAdvances() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-speechFixtures", "YES"]
        app.launch()

        // Home → start a session. (The button carries a spoken-style
        // accessibility label, not its visual text.)
        let begin = app.buttons["Tap to begin the brain health check"]
        XCTAssertTrue(begin.waitForExistence(timeout: 30), "Home screen did not appear")
        begin.tap()

        // Welcome phase must unlock Begin Assessment (voice guide speaking via
        // clip/AVSpeech fallback; reveal falls back on a timer if synthesis
        // completion never fires on the simulator).
        // The reveal sequence is paced to the spoken intro (~130-140 wpm), so
        // the button can take ~30 s after the speech anchor to appear.
        let beginAssessment = app.buttons["Begin Assessment"]
        XCTAssertTrue(beginAssessment.waitForExistence(timeout: 75), "Welcome never unlocked Begin Assessment")
        // The button starts disabled until the reveal sequence enables it.
        let enabled = NSPredicate(format: "isEnabled == true")
        let enabledExpectation = XCTNSPredicateExpectation(predicate: enabled, object: beginAssessment)
        XCTAssertEqual(XCTWaiter().wait(for: [enabledExpectation], timeout: 60), .completed,
                       "Begin Assessment never became enabled")
        beginAssessment.tap()

        // Orientation question 1 appears...
        let q1 = app.staticTexts["What country is this?"]
        XCTAssertTrue(q1.waitForExistence(timeout: 30), "Orientation question 1 never appeared")

        // ...and must ADVANCE to question 2 (speech presence detected via the
        // voice-mode ASR window + fixture). Generous timeout: question speech
        // (or its 14 s fallback) + 1.5 s fixture + 1 s advance delay.
        let q2 = app.staticTexts["What year is this?"]
        XCTAssertTrue(q2.waitForExistence(timeout: 60),
                      "Orientation never advanced — voice-mode patient-speaking bridge did not fire")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
