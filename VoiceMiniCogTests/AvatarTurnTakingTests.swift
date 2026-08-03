//
//  AvatarTurnTakingTests.swift
//  VoiceMiniCogTests
//
//  Behavioral tests for the recall/orientation "not listening" + word
//  registration crash fixes. Covers:
//   - `AutoInterruptDecision.decide` — phase-scoping + min-duration gate
//   - `VoiceIsolationSyncState` — hard-gate state transitions
//   - `TavusError.personaSyncUnverified` — user-facing copy contract
//
//  These tests intentionally avoid spinning up a CallClient / URLSession so
//  they stay fast and deterministic. End-to-end join / PATCH integration is
//  still exercised on device during QA.
//

import XCTest
@testable import VoiceMiniCog

// MARK: - AutoInterruptDecision

final class AutoInterruptDecisionTests: XCTestCase {

    // MARK: Echo conflict takes priority

    func testSkipsWhenEchoInFlight_evenForLongUtterance() {
        let decision = AutoInterruptDecision.decide(
            echoInFlight: true,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: false,
            utteranceDuration: 5.0,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "echo-conflict"))
    }

    func testSkipsWhenQueueNonEmpty_evenInIntroPhase() {
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 2,
            allowInterrupt: true,
            isScriptedPhase: false,
            utteranceDuration: 3.0,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "echo-conflict"))
    }

    // MARK: Join-guard window

    func testSkipsDuringJoinGuard() {
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: false,
            isScriptedPhase: false,
            utteranceDuration: 4.0,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "join-guard"))
    }

    // MARK: Phase-scoping — the core word-recall / orientation fix

    func testSkipsInScriptedPhase_wordRecall() {
        // Even with a long, post-guard utterance, scripted phases MUST NOT
        // fire the auto-interrupt drain. Previously this was clobbering the
        // patient's just-spoken recall response via overwrite_llm_context.
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: true,
            utteranceDuration: 3.5,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "phase-gated"))
    }

    func testSkipsInScriptedPhase_overridesMinDurationPath() {
        // A 2-second utterance would pass the min-duration gate, but
        // scripted-phase skip takes priority — there's no scenario where
        // a scripted phase should drain the LLM on user stopped_speaking.
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: true,
            utteranceDuration: 2.0,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "phase-gated"))
    }

    // MARK: Min-duration gate for non-scripted phases

    func testSkipsBriefUtteranceInIntroPhase() {
        // Cough / filler in intro phase — skip even though intro normally
        // allows the drain. 800ms is a typical cough duration.
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: false,
            utteranceDuration: 0.8,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "below-min-duration"))
    }

    func testSkipsZeroDurationUtterance() {
        // Orphan stopped_speaking with no prior started_speaking → duration 0.
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: false,
            utteranceDuration: 0.0,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .skip(reason: "below-min-duration"))
    }

    func testFiresAtExactlyMinDuration() {
        // Boundary: exactly 1.2s is allowed (>= comparison).
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: false,
            utteranceDuration: 1.2,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .fire(reason: "user-driven"))
    }

    // MARK: Happy path — intro / outro with real utterance

    func testFiresInIntroWithNormalUtterance() {
        let decision = AutoInterruptDecision.decide(
            echoInFlight: false,
            queueDepth: 0,
            allowInterrupt: true,
            isScriptedPhase: false,
            utteranceDuration: 2.5,
            minDurationForInterrupt: 1.2
        )
        XCTAssertEqual(decision, .fire(reason: "user-driven"))
    }

    // MARK: Response-mark classification

    func testResponseMarkTaxonomy() {
        XCTAssertEqual(AutoInterruptDecision.responseMark(for: "echo-conflict"), "ignored")
        XCTAssertEqual(AutoInterruptDecision.responseMark(for: "join-guard"), "final")
        XCTAssertEqual(AutoInterruptDecision.responseMark(for: "phase-gated"), "final")
        XCTAssertEqual(AutoInterruptDecision.responseMark(for: "below-min-duration"), "partial")
        XCTAssertEqual(AutoInterruptDecision.responseMark(for: "unexpected"), "unknown")
    }
}

// MARK: - VoiceIsolationSyncState

final class VoiceIsolationSyncStateTests: XCTestCase {

    func testIdleIsNotTerminal() {
        let state: VoiceIsolationSyncState = .idle
        XCTAssertFalse(state.isTerminalSuccess)
        XCTAssertFalse(state.isTerminalFailure)
    }

    func testSyncingIsNotTerminal() {
        let state: VoiceIsolationSyncState = .syncing(attempt: 1)
        XCTAssertFalse(state.isTerminalSuccess)
        XCTAssertFalse(state.isTerminalFailure)
    }

    func testVerifiedIsTerminalSuccess() {
        let state: VoiceIsolationSyncState = .verified
        XCTAssertTrue(state.isTerminalSuccess)
        XCTAssertFalse(state.isTerminalFailure)
    }

    func testFailedIsTerminalFailure() {
        let state: VoiceIsolationSyncState = .failed(reason: "HTTP 500")
        XCTAssertFalse(state.isTerminalSuccess)
        XCTAssertTrue(state.isTerminalFailure)
    }

    func testSyncingAttemptsAreDistinct() {
        // Equatable discrimination — attempt number matters for the UI
        // progress readout ("Syncing avatar config (attempt 2 of 3)...").
        XCTAssertNotEqual(
            VoiceIsolationSyncState.syncing(attempt: 1),
            VoiceIsolationSyncState.syncing(attempt: 2)
        )
    }
}

// MARK: - TavusError.personaSyncUnverified copy

final class TavusErrorCopyTests: XCTestCase {

    func testPersonaSyncUnverifiedSurfacesReasonToUser() {
        // Clinicians and patients both see this copy. It must NOT be a
        // generic "something went wrong" — it must indicate the assessment
        // cannot start and surface the underlying reason.
        let err = TavusError.personaSyncUnverified(reason: "HTTP 500: internal server error")
        let description = err.errorDescription ?? ""
        XCTAssertTrue(description.contains("cannot start") || description.contains("Cannot start"),
                      "Expected 'Cannot start assessment' copy, got: \(description)")
        XCTAssertTrue(description.contains("HTTP 500"),
                      "Expected underlying reason in copy, got: \(description)")
    }

    func testUnverifiedErrorIsDistinctFromApiError() {
        // Exhaustive switches on TavusError elsewhere in the app must
        // handle the new case explicitly — if this test compiles it means
        // the enum case exists in scope.
        let err: TavusError = .personaSyncUnverified(reason: "x")
        if case .apiError = err {
            XCTFail("personaSyncUnverified must not be confused with apiError")
        }
    }
}
