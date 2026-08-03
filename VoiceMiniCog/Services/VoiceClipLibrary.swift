//
//  VoiceClipLibrary.swift
//  VoiceMiniCog
//
//  Maps echo text → pre-rendered audio clip. Text is normalized
//  (SSML stripped, whitespace collapsed) and SHA-256 hashed; the hash
//  keys into VoiceClipManifest.json bundled under Resources/VoiceClips/.
//  Provenance discipline mirrors the six-module spec's stimulus
//  fingerprinting: any script text change changes the hash and is caught
//  by VoiceClipManifestTests.
//

import CryptoKit
import Foundation

struct VoiceClipManifest: Codable, Equatable {
    struct Clip: Codable, Equatable {
        let id: String
        let scriptSHA256: String
        let file: String
        let durationMs: Int
        /// false until the real ElevenLabs render replaces placeholders.
        let rendered: Bool
        var voiceId: String? = nil
        var modelId: String? = nil
        var renderedAt: String? = nil
    }
    var clips: [Clip]
}

/// `nonisolated`: this project defaults every type to MainActor isolation
/// (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor). A plain class implicitly
/// inheriting that isolation gets an *isolated deinit*, which on the
/// Xcode 26.2 / iOS 26.2 Simulator runtime routes deallocation through a
/// buggy `swift_task_deinitOnExecutorMainActorBackDeploy` back-deployment
/// shim that bad-frees an internal TaskLocal bookkeeping object (confirmed
/// via AddressSanitizer: bad-free in swift::TaskLocal::StopLookupScope
/// during VoiceClipLibrary's __deallocating_deinit). This type holds no
/// actor-isolated state and is safe to use from any context, so opting out
/// of default isolation is both correct and avoids the crash.
nonisolated final class VoiceClipLibrary {

    private let manifest: VoiceClipManifest
    private let bundle: Bundle
    private let byHash: [String: VoiceClipManifest.Clip]

    init(manifest: VoiceClipManifest, bundle: Bundle) {
        self.manifest = manifest
        self.bundle = bundle
        self.byHash = Dictionary(
            manifest.clips.map { ($0.scriptSHA256, $0) },
            uniquingKeysWith: { first, _ in first })
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> VoiceClipLibrary {
        guard let url = bundle.url(forResource: "VoiceClipManifest",
                                   withExtension: "json",
                                   subdirectory: "VoiceClips")
            ?? bundle.url(forResource: "VoiceClipManifest", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest = try JSONDecoder().decode(VoiceClipManifest.self,
                                                from: Data(contentsOf: url))
        return VoiceClipLibrary(manifest: manifest, bundle: bundle)
    }

    /// Strip SSML wrappers/tags and collapse whitespace so hashes are stable
    /// across SSML and plain variants of the same script.
    static func normalize(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "<speak>", with: "")
        t = t.replacingOccurrences(of: "</speak>", with: "")
        t = t.replacingOccurrences(of: "<break[^>]*/>", with: " ",
                                   options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ",
                                   options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sha256(of text: String) -> String {
        let digest = SHA256.hash(data: Data(normalize(text).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func entry(forText text: String) -> VoiceClipManifest.Clip? {
        byHash[Self.sha256(of: text)]
    }

    func clipURL(for clip: VoiceClipManifest.Clip) -> URL? {
        bundle.url(forResource: (clip.file as NSString).deletingPathExtension,
                   withExtension: (clip.file as NSString).pathExtension,
                   subdirectory: "VoiceClips")
    }

    var allClips: [VoiceClipManifest.Clip] { manifest.clips }
}
