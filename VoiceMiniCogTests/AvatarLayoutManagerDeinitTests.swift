//
//  AvatarLayoutManagerDeinitTests.swift
//  VoiceMiniCogTests
//
//  REGRESSION GUARD for crash incident 230A96F5 (2026-08-05).
//
//  AvatarLayoutManager is @MainActor. Without an explicit `nonisolated deinit`
//  the compiler synthesizes an ISOLATED deinit, which Xcode 26.2 routes through
//  swift_task_deinitOnExecutorMainActorBackDeploy — a shim that double-frees a
//  TaskLocal object and aborts the process.
//
//  Production impact: the crash fired on the .sessionAbandoned path (150 s of
//  patient silence), i.e. exactly when the partial score report should have been
//  generated. Deleting the `nonisolated deinit` reintroduces a clinical-safety
//  crash.
//

import XCTest
@testable import VoiceMiniCog

@MainActor
final class AvatarLayoutManagerDeinitTests: XCTestCase {

    /// Repeated create/destroy cycles. Under the isolated-deinit bug this
    /// aborts the test host rather than failing an assertion.
    func testRepeatedDeallocationDoesNotAbort() {
        for _ in 0..<200 {
            var m: AvatarLayoutManager? = AvatarLayoutManager()
            m?.currentPhase = .welcome
            m = nil
        }
        XCTAssertTrue(true, "survived 200 dealloc cycles without abort")
    }

    /// Deallocation while an acknowledge task may be outstanding — the state
    /// the synthesized deinit had to clean up.
    func testDeallocationWithPendingWorkDoesNotAbort() {
        for _ in 0..<50 {
            var m: AvatarLayoutManager? = AvatarLayoutManager()
            m?.isTransitioning = true
            m = nil
        }
        XCTAssertTrue(true, "survived dealloc with in-flight state")
    }
}
