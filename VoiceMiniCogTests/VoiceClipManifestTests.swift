//
//  VoiceClipManifestTests.swift
//  VoiceMiniCogTests
//
//  DRIFT GUARD (release blocker, same posture as BatteryEnumSyncTests):
//  every speakable surface must have a manifest entry whose hash matches
//  its current text. A failing test means script text changed without a
//  re-render, or a new script has no clip.
//

import XCTest
@testable import VoiceMiniCog

@MainActor
class VoiceClipManifestTests: XCTestCase {

    func testEveryInventoryItemHasManifestEntry() throws {
        let library = try VoiceClipLibrary.loadFromBundle()
        var missing: [String] = []
        for item in VoiceScriptInventory.allItems {
            if library.entry(forText: item.text) == nil {
                missing.append(item.id)
            }
        }
        XCTAssertTrue(missing.isEmpty,
            "No clip manifest entry for: \(missing.joined(separator: ", ")). " +
            "Run scripts/render_voice_clips.py to render + update the manifest.")
    }

    func testEveryRenderedClipFileExistsInBundle() throws {
        let library = try VoiceClipLibrary.loadFromBundle()
        var missingFiles: [String] = []
        for clip in library.allClips where clip.rendered {
            if library.clipURL(for: clip) == nil {
                missingFiles.append(clip.file)
            }
        }
        XCTAssertTrue(missingFiles.isEmpty,
            "Manifest marks these rendered but files are missing from bundle: \(missingFiles)")
    }

    func testNoDuplicateHashes() throws {
        let library = try VoiceClipLibrary.loadFromBundle()
        let hashes = library.allClips.map(\.scriptSHA256)
        XCTAssertEqual(hashes.count, Set(hashes).count, "Duplicate scriptSHA256 in manifest")
    }

    /// Dev utility disguised as a test: dumps the inventory JSON the render
    /// script consumes. Always passes.
    func testExportInventoryJSON() throws {
        let items = VoiceScriptInventory.allItems.map {
            ["id": $0.id,
             "text": $0.text,
             "normalized": VoiceClipLibrary.normalize($0.text),
             "scriptSHA256": VoiceClipLibrary.sha256(of: $0.text)]
        }
        let data = try JSONSerialization.data(withJSONObject: items,
                                              options: [.prettyPrinted, .sortedKeys])
        let url = URL(fileURLWithPath: "/tmp/voice_script_inventory.json")
        try data.write(to: url)
        print("Inventory exported: \(url.path) (\(items.count) items)")
    }
}
