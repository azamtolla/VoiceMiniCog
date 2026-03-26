//
//  ScriptClipPlayer.swift
//  VoiceMiniCog
//
//  Loads pre-rendered ElevenLabs PCM clips from bundle, validates against
//  ClipManifest.json, injects into Tavus via PersonaBridge.sendEcho().
//  Falls back to text via sendRespond() if audio file is missing.
//

import Foundation

struct ClipManifestEntry: Codable {
    let id: String
    let file: String
    let transcript: String
}

struct ClipManifest: Codable {
    let clips: [ClipManifestEntry]
}

final class ScriptClipPlayer {
    weak var personaBridge: PersonaBridge?
    weak var audioArbitrator: AudioArbitrator?

    private var manifest: [String: ClipManifestEntry] = [:]

    init() { loadManifest() }

    private func loadManifest() {
        guard let url = Bundle.main.url(forResource: "ClipManifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(ClipManifest.self, from: data)
        else { print("[ScriptClipPlayer] WARNING: ClipManifest.json not found"); return }
        for entry in parsed.clips { manifest[entry.id] = entry }
        print("[ScriptClipPlayer] Loaded \(manifest.count) clip entries")
    }

    func playClip(id: String) async {
        guard let entry = manifest[id] else {
            print("[ScriptClipPlayer] WARNING: Unknown clip '\(id)'"); return
        }
        guard let bridge = personaBridge, let arb = audioArbitrator else {
            print("[ScriptClipPlayer] ERROR: bridge/arbitrator not set"); return
        }

        await arb.acquireToken(source: .scriptedClip)
        await bridge.holdPersonaPlex()
        await arb.waitForReplicaStopped(inferenceId: nil, timeoutSeconds: 3.0)

        let resName = (entry.file as NSString).deletingPathExtension
        if let clipURL = Bundle.main.url(forResource: resName, withExtension: "pcm"),
           let clipData = try? Data(contentsOf: clipURL), clipData.count > 0 {
            await bridge.sendEchoInteraction(clipData: clipData, clipId: id, transcript: entry.transcript)
            print("[ScriptClipPlayer] Sent echo: \(id) (\(clipData.count) bytes)")
        } else {
            print("[ScriptClipPlayer] WARNING: Missing audio for '\(id)', fallback to text")
            await bridge.sendRespondInteraction(text: entry.transcript)
        }

        await arb.waitForReplicaStopped(inferenceId: id, timeoutSeconds: 10.0)
        arb.releaseToken()
        await bridge.releasePersonaPlex()
        print("[ScriptClipPlayer] Clip complete: \(id)")
    }

    func playClips(_ ids: [String]) async {
        for id in ids { await playClip(id: id) }
    }

    func transcript(for clipId: String) -> String? { manifest[clipId]?.transcript }
    func hasClip(_ clipId: String) -> Bool { manifest[clipId] != nil }
}
