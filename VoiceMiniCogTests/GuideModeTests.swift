//
//  GuideModeTests.swift
//  VoiceMiniCogTests
//

import XCTest
@testable import VoiceMiniCog

@MainActor
class GuideModeTests: XCTestCase {

    func testDefaultsToVoiceWhenNoTavusKey() {
        XCTAssertEqual(GuideMode.resolved(storedRawValue: nil, tavusKeyConfigured: false), .voice)
    }

    func testDefaultsToAvatarWhenTavusKeyConfigured() {
        XCTAssertEqual(GuideMode.resolved(storedRawValue: nil, tavusKeyConfigured: true), .avatar)
    }

    func testStoredChoiceWinsOverDefault() {
        XCTAssertEqual(GuideMode.resolved(storedRawValue: "voice", tavusKeyConfigured: true), .voice)
        XCTAssertEqual(GuideMode.resolved(storedRawValue: "avatar", tavusKeyConfigured: true), .avatar)
    }

    func testAvatarChoiceFallsBackToVoiceWithoutKey() {
        // Avatar mode is unusable without a Tavus key — never resolve to it.
        XCTAssertEqual(GuideMode.resolved(storedRawValue: "avatar", tavusKeyConfigured: false), .voice)
    }

    func testRefusalCopyHasAllEightCategoriesPlusSystem() {
        // 8 behavioral-guide refusals + emergency + reengagement
        XCTAssertEqual(VoiceRefusalCopy.allEntries.count, 10)
        XCTAssertFalse(VoiceRefusalCopy.allEntries.contains { $0.text.isEmpty })
    }
}
