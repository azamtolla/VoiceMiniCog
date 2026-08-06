//
//  VoiceGuideServiceTests.swift
//  VoiceMiniCogTests
//

import XCTest
@testable import VoiceMiniCog

@MainActor
class VoiceGuideServiceTests: XCTestCase {

    private func makeService() -> VoiceGuideService {
        let manifest = VoiceClipManifest(clips: [])
        let library = VoiceClipLibrary(manifest: manifest, bundle: .main)
        // playbackDisabledForTesting: completes each utterance synchronously
        // without touching AVAudioPlayer/AVSpeechSynthesizer.
        return VoiceGuideService(library: library, playbackDisabledForTesting: true)
    }

    func testEchoRequestPostsStartedAndDone() {
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        let started = expectation(forNotification: .avatarStartedSpeaking, object: nil)
        let done = expectation(forNotification: .avatarDoneSpeaking, object: nil)
        avatarSpeak("Hello there.")
        wait(for: [started, done], timeout: 2.0)
    }

    func testInterruptClearsQueueAndPostsDone() {
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        service.enqueueForTesting(["one", "two", "three"])
        let done = expectation(forNotification: .avatarDoneSpeaking, object: nil)
        avatarInterrupt()
        wait(for: [done], timeout: 2.0)
        XCTAssertEqual(service.queueDepthForTesting, 0)
        XCTAssertFalse(service.isSpeaking)
    }

    func testDeactivateStopsObserving() {
        let service = makeService()
        service.activate()
        service.deactivate()
        let started = expectation(forNotification: .avatarStartedSpeaking, object: nil)
        started.isInverted = true
        avatarSpeak("Should be ignored.")
        wait(for: [started], timeout: 1.0)
    }

    func testEmptyTextIsIgnored() {
        let service = makeService()
        service.activate()
        defer { service.deactivate() }
        // avatarSpeak guards empty; post directly to exercise service guard.
        let started = expectation(forNotification: .avatarStartedSpeaking, object: nil)
        started.isInverted = true
        NotificationCenter.default.post(name: .tavusEchoRequest, object: nil,
                                        userInfo: ["text": "  "])
        wait(for: [started], timeout: 1.0)
    }

    // MARK: - Probes beyond the plan's five (order, duplicates, idle
    // interrupt, watchdog fire path, stale-service disarm)

    func testQueuePreservesOrderIncludingDuplicates() {
        // Clinical scripts are sequential — a reordered queue means
        // instructions out of order. Duplicated text must play twice.
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        service.enqueueForTesting(["one", "two"])
        avatarSpeak("one") // duplicate of the queue head, and the drain trigger
        XCTAssertEqual(service.spokenTextsForTesting, ["one", "two", "one"])
        XCTAssertEqual(service.queueDepthForTesting, 0)
        XCTAssertFalse(service.isSpeaking)
    }

    func testDoneFiresOncePerQueueDrainStartedPerUtterance() {
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        var startedCount = 0
        var doneCount = 0
        let s = NotificationCenter.default.addObserver(
            forName: .avatarStartedSpeaking, object: nil, queue: .main) { _ in startedCount += 1 }
        let d = NotificationCenter.default.addObserver(
            forName: .avatarDoneSpeaking, object: nil, queue: .main) { _ in doneCount += 1 }
        defer {
            NotificationCenter.default.removeObserver(s)
            NotificationCenter.default.removeObserver(d)
        }

        service.enqueueForTesting(["a", "b"])
        avatarSpeak("c")
        XCTAssertEqual(startedCount, 3, "one .avatarStartedSpeaking per utterance")
        XCTAssertEqual(doneCount, 1, ".avatarDoneSpeaking once, at queue drain")
    }

    func testIdleInterruptDoesNotPostSpuriousDone() {
        // Every phase view calls avatarInterrupt() in onAppear before its
        // first prompt (QAPhaseView.swift:52). In avatar mode an interrupt
        // while the replica is silent produces no stopped_speaking event, so
        // voice mode must not fabricate a done — phase views pace on it.
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        let done = expectation(forNotification: .avatarDoneSpeaking, object: nil)
        done.isInverted = true
        avatarInterrupt()
        wait(for: [done], timeout: 1.0)
        XCTAssertFalse(service.isSpeaking)
    }

    func testExplicitCancelDisarmsSilenceWatch() {
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        NotificationCenter.default.post(name: .tavusBeginSilenceWatchRequest, object: nil)
        XCTAssertTrue(service.silenceWatchArmedForTesting)
        NotificationCenter.default.post(name: .tavusCancelSilenceWatchRequest, object: nil)
        XCTAssertFalse(service.silenceWatchArmedForTesting)
    }

    func testDeactivateDisarmsSilenceWatch() {
        // A stale service must not fire .sessionAbandoned after session end.
        let service = makeService()
        service.activate()
        NotificationCenter.default.post(name: .tavusBeginSilenceWatchRequest, object: nil)
        XCTAssertTrue(service.silenceWatchArmedForTesting)
        service.deactivate()
        XCTAssertFalse(service.silenceWatchArmedForTesting)
    }

    func testSilenceWatchFiresReengagementThenAbandonment() {
        // Compressed intervals (0.1 s / 0.4 s) exercise the REAL fire path:
        // reengagement speaks, abandonment posts .sessionAbandoned with the
        // exact userInfo shape ContentView parses (DailyCallManager.swift:808-815).
        //
        // Runs on a PRIVATE NotificationCenter: a real .sessionAbandoned on
        // .default reaches the test host app's ContentView, whose assessment-
        // teardown deallocates AvatarLayoutManager and crashes on the
        // pre-existing Xcode 26.2 MainActor-deinit back-deploy bug
        // (SIGABRT in swift_task_deinitOnExecutorMainActorBackDeploy —
        // same bug PDFInspectionTests hits).
        let center = NotificationCenter()
        let library = VoiceClipLibrary(manifest: VoiceClipManifest(clips: []), bundle: .main)
        let service = VoiceGuideService(library: library,
                                        playbackDisabledForTesting: true,
                                        reengagementAfter: 0.1,
                                        abandonmentAfter: 0.4,
                                        notificationCenter: center)
        service.activate()
        defer { service.deactivate() }

        let reengaged = XCTNSNotificationExpectation(
            name: .avatarStartedSpeaking, object: nil, notificationCenter: center)
        let abandoned = XCTNSNotificationExpectation(
            name: .sessionAbandoned, object: nil, notificationCenter: center)
        abandoned.handler = { note in
            guard let raw = note.userInfo?["reason"] as? String,
                  let duration = note.userInfo?["silenceDuration"] as? Double else {
                XCTFail("sessionAbandoned userInfo missing reason/silenceDuration")
                return true
            }
            XCTAssertEqual(SessionShutdownReason(rawValue: raw), .abandonedSilence,
                           "wrong reason string would silently record .unknown on the partial report")
            XCTAssertGreaterThanOrEqual(duration, 0.3)
            return true
        }
        center.post(name: .tavusBeginSilenceWatchRequest, object: nil)
        XCTAssertTrue(service.silenceWatchArmedForTesting)
        wait(for: [reengaged, abandoned], timeout: 5.0)
        XCTAssertFalse(service.silenceWatchArmedForTesting, "abandonment must disarm the watch")
        XCTAssertEqual(service.spokenTextsForTesting, [VoiceRefusalCopy.reengagement.text])
    }

    func testPatientSpeechCancelsSilenceWatch() {
        // Guards the MAJOR failure mode: without cancellation, the
        // reengagement clip plays mid-answer at 90 s and .sessionAbandoned
        // fires at 150 s during a normally-progressing session.
        let service = makeService()
        service.activate()
        defer { service.deactivate() }

        NotificationCenter.default.post(name: .tavusBeginSilenceWatchRequest, object: nil)
        XCTAssertTrue(service.silenceWatchArmedForTesting)
        NotificationCenter.default.post(name: .patientStartedSpeaking, object: nil)
        let settled = expectation(description: "observer ran")
        DispatchQueue.main.async { settled.fulfill() }
        wait(for: [settled], timeout: 1.0)
        XCTAssertFalse(service.silenceWatchArmedForTesting)
    }
}
