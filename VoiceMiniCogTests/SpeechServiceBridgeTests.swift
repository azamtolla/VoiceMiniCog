//
//  SpeechServiceBridgeTests.swift
//  VoiceMiniCogTests
//
//  Task 4B: SpeechService → patient-speaking notification bridge.
//
//  Phase views advance on .patientStartedSpeaking → .patientDoneSpeaking
//  (QAPhaseView.swift:78-88). In voice mode the only historical posters
//  (TavusCVIView, DailyCallManager) are inactive, so SpeechService must
//  bridge on-device ASR activity to those notifications — gated on
//  GuideMode so avatar mode never double-posts, and suppressed while the
//  voice guide itself is speaking (half-duplex) so the app's own audio
//  can't masquerade as patient speech.
//
//  Clinical stakes: a false .patientDoneSpeaking advances the assessment
//  before the patient answered (silent data loss); a missing one stalls
//  every orientation question into the 10 s no-response timeout.
//

import XCTest
@testable import VoiceMiniCog

@MainActor
class SpeechServiceBridgeTests: XCTestCase {

    /// Voice-mode service with an injected mode so tests are deterministic
    /// regardless of the test host's Keychain (Tavus key) or UserDefaults.
    /// `bridgeGraceAfterGuideSpeech = 0` unless a test exercises the grace
    /// window explicitly.
    private func makeVoiceService(grace: TimeInterval = 0) -> SpeechService {
        let service = SpeechService()
        service.guideModeProvider = { .voice }
        service.bridgeGraceAfterGuideSpeech = grace
        return service
    }

    // MARK: - Plan tests (Task 4B Step 2)

    func testFirstPartialPostsPatientStartedOncePerWindow() {
        let service = makeVoiceService()
        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.expectedFulfillmentCount = 1
        started.assertForOverFulfill = true
        service.simulatePartialTranscriptForTesting("dog")
        service.simulatePartialTranscriptForTesting("dog rain") // same window — no second post
        wait(for: [started], timeout: 1.0)
    }

    func testFinalizePostsPatientDone() {
        let service = makeVoiceService()
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        service.simulatePartialTranscriptForTesting("butter")
        service.simulateFinalTranscriptForTesting("butter")
        wait(for: [done], timeout: 1.0)
    }

    // MARK: - Window state machine

    /// A final result with no preceding partial (short single-shot utterance)
    /// must still produce started → done — the real recognizer callback runs
    /// a final result through the partial path (transcript set) before the
    /// stop path.
    func testFinalWithoutPriorPartialPostsStartedThenDone() {
        let service = makeVoiceService()
        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.assertForOverFulfill = true
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.assertForOverFulfill = true
        service.simulateFinalTranscriptForTesting("eleven ten")
        wait(for: [started, done], timeout: 1.0, enforceOrder: true)
    }

    /// PROBE 1: a stray partial arriving AFTER finalization (queued recognizer
    /// callback racing stopListening) must NOT re-fire .patientStartedSpeaking
    /// — that would falsely cancel the next silence watch and could unlock a
    /// phase advance with no real speech.
    func testPartialAfterFinalizationDoesNotRefireStarted() {
        let service = makeVoiceService()
        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.expectedFulfillmentCount = 1
        started.assertForOverFulfill = true
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.expectedFulfillmentCount = 1
        done.assertForOverFulfill = true

        service.simulatePartialTranscriptForTesting("butter")
        service.simulateFinalTranscriptForTesting("butter")
        service.simulatePartialTranscriptForTesting("butter again") // stray post-final
        wait(for: [started, done], timeout: 1.0)
    }

    /// PROBE 2: consecutive answer windows. startListening() opens a fresh
    /// window, so window 2 must post its own started/done pair.
    func testConsecutiveWindowsEachPostStartedAndDone() async throws {
        let service = makeVoiceService()
        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.expectedFulfillmentCount = 2
        started.assertForOverFulfill = true
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.expectedFulfillmentCount = 2
        done.assertForOverFulfill = true

        // Window 1
        try await service.startListening()   // simulator path: no audio HW touched
        service.simulatePartialTranscriptForTesting("north")
        service.simulateFinalTranscriptForTesting("north dakota")
        // Window 2
        try await service.startListening()
        service.simulatePartialTranscriptForTesting("july")
        service.simulateFinalTranscriptForTesting("july fourth")

        await fulfillment(of: [started, done], timeout: 2.0)
    }

    /// A window that heard speech but is closed by stopListening() (phase view
    /// timer, error path) — not by an isFinal result — must still post done,
    /// or QAPhaseView waits out the full no-response timeout despite speech.
    func testStopListeningAfterSpeechPostsDone() {
        let service = makeVoiceService()
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.assertForOverFulfill = true
        service.simulatePartialTranscriptForTesting("the clock stopped")
        service.stopListening()
        wait(for: [done], timeout: 1.0)
    }

    /// stopListening() on a window with NO speech must post nothing —
    /// a fabricated done would advance QAPhaseView on silence.
    func testStopListeningWithoutSpeechPostsNothing() {
        let service = makeVoiceService()
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.isInverted = true
        service.stopListening()
        wait(for: [done], timeout: 0.5)
    }

    /// Whitespace-only partials (recognizer noise) must not open a window.
    func testWhitespacePartialDoesNotPostStarted() {
        let service = makeVoiceService()
        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.isInverted = true
        service.simulatePartialTranscriptForTesting("   ")
        wait(for: [started], timeout: 0.5)
    }

    // MARK: - Mode gate (PROBE 3)

    /// In avatar mode the bridge must be COMPLETELY silent — Daily's
    /// user.started/stopped_speaking events own these posts there, and a
    /// second poster would double-advance QAPhaseView.
    func testAvatarModeBridgePostsNothing() {
        let service = SpeechService()
        service.guideModeProvider = { .avatar }
        service.bridgeGraceAfterGuideSpeech = 0

        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.isInverted = true
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.isInverted = true

        service.simulatePartialTranscriptForTesting("dog")
        service.simulateFinalTranscriptForTesting("dog rain butter")
        service.stopListening()
        wait(for: [started, done], timeout: 0.5)
    }

    // MARK: - Half-duplex gate

    /// While the voice guide is speaking (e.g. the 90 s reengagement clip
    /// playing into an open listening window), ASR activity is the app
    /// hearing itself: it must neither post started (which would falsely
    /// cancel the silence watchdog) nor lead to a done.
    func testPartialWhileGuideSpeakingIsSuppressed() {
        let service = makeVoiceService()
        NotificationCenter.default.post(name: .avatarStartedSpeaking, object: nil)
        defer { NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil) }

        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.isInverted = true
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)
        done.isInverted = true

        service.simulatePartialTranscriptForTesting("are you still there")
        service.stopListening() // suppressed window ⇒ nothing to finalize
        wait(for: [started, done], timeout: 0.5)
    }

    /// PROBE 4: the gate must re-enable after the guide stops speaking —
    /// the first patient partial after .avatarDoneSpeaking posts started.
    func testGateReenablesAfterGuideDoneSpeaking() {
        let service = makeVoiceService(grace: 0)
        NotificationCenter.default.post(name: .avatarStartedSpeaking, object: nil)
        service.simulatePartialTranscriptForTesting("take your time") // guide echo — suppressed
        NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil)

        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.expectedFulfillmentCount = 1
        started.assertForOverFulfill = true
        let done = expectation(forNotification: .patientDoneSpeaking, object: nil)

        service.simulatePartialTranscriptForTesting("nineteen forty two")
        service.simulateFinalTranscriptForTesting("nineteen forty two")
        wait(for: [started, done], timeout: 1.0)
    }

    /// SFSpeechRecognizer partials trail the audio by 100-500 ms, so a
    /// transcription of the guide's own tail can arrive AFTER
    /// .avatarDoneSpeaking flips the flag. A grace interval after guide
    /// speech absorbs those trailing partials.
    func testTrailingPartialWithinGraceIntervalIsSuppressed() {
        let service = makeVoiceService(grace: 60) // effectively infinite for the test
        NotificationCenter.default.post(name: .avatarStartedSpeaking, object: nil)
        NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil)

        let started = expectation(forNotification: .patientStartedSpeaking, object: nil)
        started.isInverted = true
        service.simulatePartialTranscriptForTesting("still there take your time")
        wait(for: [started], timeout: 0.5)
    }
}
