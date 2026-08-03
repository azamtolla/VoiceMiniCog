//
//  TavusSyncCooldownTests.swift
//  VoiceMiniCogTests
//
//  Tests for the welcome-screen sync-failure loop fix:
//   - `PersonaSyncCooldown.decide` — short-circuit contract for repeated
//     sync attempts after a terminal failure.
//   - `TavusService.buildTavusRequest` — URLSession cache policy and
//     conditional-header hygiene (the root cause of the abnormal
//     304 Not Modified responses on PATCH).
//

import XCTest
@testable import VoiceMiniCog

// MARK: - PersonaSyncCooldown

final class PersonaSyncCooldownTests: XCTestCase {

    func testCooldownActiveInsideWindow() {
        let lastFailure = Date()
        let now = lastFailure.addingTimeInterval(5)
        let decision = PersonaSyncCooldown.decide(
            lastTerminalFailureAt: lastFailure,
            now: now,
            window: 30
        )
        guard case .cooldownActive(let remaining) = decision else {
            XCTFail("Expected .cooldownActive, got \(decision)")
            return
        }
        // 30s window - 5s elapsed = 25s remaining
        XCTAssertEqual(remaining, 25, accuracy: 0.001)
    }

    func testCooldownExpiredAtWindowBoundary() {
        let lastFailure = Date()
        let now = lastFailure.addingTimeInterval(30)
        let decision = PersonaSyncCooldown.decide(
            lastTerminalFailureAt: lastFailure,
            now: now,
            window: 30
        )
        XCTAssertEqual(decision, .expired)
    }

    func testCooldownExpiredBeyondWindow() {
        let lastFailure = Date()
        let now = lastFailure.addingTimeInterval(45)
        let decision = PersonaSyncCooldown.decide(
            lastTerminalFailureAt: lastFailure,
            now: now,
            window: 30
        )
        XCTAssertEqual(decision, .expired)
    }

    func testCooldownActiveImmediatelyAfterFailure() {
        // Zero-elapsed-time case: user taps Start right after prewarm fails.
        // Must be cooldown-active with the full window remaining.
        let lastFailure = Date()
        let decision = PersonaSyncCooldown.decide(
            lastTerminalFailureAt: lastFailure,
            now: lastFailure,
            window: 30
        )
        guard case .cooldownActive(let remaining) = decision else {
            XCTFail("Expected .cooldownActive, got \(decision)")
            return
        }
        XCTAssertEqual(remaining, 30, accuracy: 0.001)
    }

    func testDecideDoesNotProduceShouldRetry() {
        // `.shouldRetry` is reserved for the explicit user-initiated bypass
        // (Retry button) and MUST NOT be produced by the pure decision
        // function — bypass is represented by not calling decide at all.
        let lastFailure = Date()
        let decision = PersonaSyncCooldown.decide(
            lastTerminalFailureAt: lastFailure,
            now: lastFailure.addingTimeInterval(15),
            window: 30
        )
        if case .shouldRetry = decision {
            XCTFail("decide() must never return .shouldRetry — reserved for manual bypass")
        }
    }

    func testReproducesWelcomeScreenStormScenario() {
        // Mirrors the log evidence: after prewarm exhausts all 3 attempts,
        // the user taps Start and a second 9-PATCH storm fires. With the
        // cooldown in place, that second storm short-circuits.
        //
        // Timeline:
        //   t=0s     prewarm exhausts attempts → lastTerminalFailureAt = t0
        //   t=4s     user taps Start → Canvas isActive → createConversation
        //            → ensurePersonaSyncVerified(bypassCooldown: false)
        //            should see .cooldownActive and skip the network round.
        let storedFailure = Date()
        let userTapStartAt = storedFailure.addingTimeInterval(4)

        let decision = PersonaSyncCooldown.decide(
            lastTerminalFailureAt: storedFailure,
            now: userTapStartAt,
            window: TavusService.personaSyncCooldownWindow
        )
        guard case .cooldownActive = decision else {
            XCTFail("Welcome-screen Start tap within cooldown window must short-circuit")
            return
        }
    }
}

// MARK: - TavusService.buildTavusRequest

final class TavusRequestBuilderTests: XCTestCase {

    /// Helper to get a service instance. The singleton is intended for
    /// production use, but reading its builder output is read-only for
    /// the purposes of these tests.
    private var service: TavusService { TavusService.shared }

    func testPatchRequestDisablesProtocolCache() throws {
        let url = TavusService.personaURL("test-pid")
        let req = try service.buildTavusRequest(
            url: url,
            method: "PATCH",
            bodyJSON: [["op": "add", "path": "/layers/stt/diarization", "value": true]]
        )
        // Root-cause fix: cache policy must be reloadIgnoringLocalAndRemoteCacheData
        // so URLSession won't consult URLCache and won't auto-attach
        // If-None-Match / If-Modified-Since headers from a prior GET.
        XCTAssertEqual(req.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    func testGetRequestDisablesProtocolCache() throws {
        let url = TavusService.personaURL("test-pid")
        let req = try service.buildTavusRequest(
            url: url,
            method: "GET",
            bodyJSON: nil,
            timeout: 15
        )
        XCTAssertEqual(req.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
    }

    func testRequestHasNoConditionalCacheHeaders() throws {
        let url = TavusService.personaURL("test-pid")
        let req = try service.buildTavusRequest(
            url: url,
            method: "PATCH",
            bodyJSON: [["op": "add", "path": "/foo", "value": 1]]
        )
        let headers = req.allHTTPHeaderFields ?? [:]
        // Explicit conditional-header strip in the builder. If any of these
        // ever slipped in (e.g., from a URLSession configuration override),
        // Tavus could respond 304 Not Modified to a state-changing PATCH.
        XCTAssertNil(headers["If-None-Match"])
        XCTAssertNil(headers["If-Modified-Since"])
        XCTAssertNil(headers["If-Match"])
        XCTAssertNil(headers["If-Unmodified-Since"])
        // Also check lowercase just in case.
        for name in headers.keys {
            let lower = name.lowercased()
            XCTAssertFalse(lower == "if-none-match",    "Unexpected If-None-Match header")
            XCTAssertFalse(lower == "if-modified-since", "Unexpected If-Modified-Since header")
            XCTAssertFalse(lower == "if-match",          "Unexpected If-Match header")
            XCTAssertFalse(lower == "if-unmodified-since", "Unexpected If-Unmodified-Since header")
        }
    }

    func testRequestAttachesApiKeyHeader() throws {
        let url = TavusService.personaURL("test-pid")
        let req = try service.buildTavusRequest(
            url: url,
            method: "GET"
        )
        // x-api-key is populated from the service's apiKey at request time.
        // We don't assert the value (it's runtime config); just that the
        // header is present so the builder is wiring it correctly.
        XCTAssertNotNil(req.allHTTPHeaderFields?["x-api-key"])
    }

    func testPostRequestSetsContentTypeWhenBodyProvided() throws {
        let req = try service.buildTavusRequest(
            url: URL(string: "https://tavusapi.com/v2/conversations")!,
            method: "POST",
            bodyJSON: ["persona_id": "x", "replica_id": "y"]
        )
        XCTAssertEqual(req.allHTTPHeaderFields?["Content-Type"], "application/json")
        XCTAssertNotNil(req.httpBody)
    }

    func testGetRequestWithoutBodyOmitsContentType() throws {
        let req = try service.buildTavusRequest(
            url: URL(string: "https://tavusapi.com/v2/personas/x")!,
            method: "GET",
            bodyJSON: nil
        )
        // No body → no Content-Type. Avoids misrepresenting a GET as
        // carrying a JSON payload.
        XCTAssertNil(req.allHTTPHeaderFields?["Content-Type"])
        XCTAssertNil(req.httpBody)
    }
}
