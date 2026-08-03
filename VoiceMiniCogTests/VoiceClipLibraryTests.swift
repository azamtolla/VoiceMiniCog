//
//  VoiceClipLibraryTests.swift
//  VoiceMiniCogTests
//

import XCTest
@testable import VoiceMiniCog

@MainActor
class VoiceClipLibraryTests: XCTestCase {

    // MARK: Normalization

    func testNormalizationStripsSSML() {
        let ssml = "<speak>Hello.<break time=\"700ms\"/> World.</speak>"
        XCTAssertEqual(VoiceClipLibrary.normalize(ssml), "Hello. World.")
    }

    func testNormalizationCollapsesWhitespace() {
        XCTAssertEqual(VoiceClipLibrary.normalize("  a \n b\t c  "), "a b c")
    }

    func testNormalizationIsIdempotentOnPlainText() {
        let plain = LeftPaneSpeechCopy.clockDrawingInstruction
        XCTAssertEqual(VoiceClipLibrary.normalize(plain), plain)
    }

    // MARK: Hashing + lookup

    func testKnownTextResolvesToManifestEntry() {
        let manifest = VoiceClipManifest(clips: [
            .init(id: "test.hello",
                  scriptSHA256: VoiceClipLibrary.sha256(of: "Hello."),
                  file: "test_hello.m4a",
                  durationMs: 500,
                  rendered: false)
        ])
        let library = VoiceClipLibrary(manifest: manifest, bundle: .main)
        XCTAssertNotNil(library.entry(forText: "<speak>Hello.</speak>"))
        XCTAssertNil(library.entry(forText: "Unknown text"))
    }

    func testManifestDecodesFromBundle() throws {
        let library = try VoiceClipLibrary.loadFromBundle()
        XCTAssertNotNil(library) // empty manifest is valid at this stage
    }
}
