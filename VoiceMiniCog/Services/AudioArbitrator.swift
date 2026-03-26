//
//  AudioArbitrator.swift
//  VoiceMiniCog
//
//  Single-speaker token: ensures only PersonaPlex OR a scripted clip
//  speaks at any given time. Uses async continuation for blocking waits.
//

import Foundation

enum AudioSource: String {
    case personaPlex
    case scriptedClip
}

protocol ReplicaEventObserving: AnyObject {
    func onReplicaStartedSpeaking(inferenceId: String?)
    func onReplicaStoppedSpeaking(inferenceId: String?, duration: Double?, interrupted: Bool)
    func onUserStartedSpeaking()
    func onUserStoppedSpeaking()
}

@Observable
final class AudioArbitrator: ReplicaEventObserving {

    var currentSpeaker: AudioSource? = nil
    var isReplicaSpeaking = false
    var isUserSpeaking = false

    private var tokenContinuation: CheckedContinuation<Void, Never>?
    private let maxHoldSeconds: TimeInterval = 5.0

    func acquireToken(source: AudioSource) async {
        if currentSpeaker != nil && currentSpeaker != source {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                tokenContinuation = cont
            }
        }
        currentSpeaker = source

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.maxHoldSeconds ?? 5) * 1_000_000_000))
            if self?.currentSpeaker == source {
                print("[AudioArbitrator] WARNING: Forced release after timeout")
                self?.releaseToken()
            }
        }
    }

    func releaseToken() {
        currentSpeaker = nil
        tokenContinuation?.resume()
        tokenContinuation = nil
    }

    // Wait for replica to stop speaking (3s timeout fallback)
    private var stoppedContinuations: [(String?, CheckedContinuation<Void, Never>)] = []

    func waitForReplicaStopped(inferenceId: String?, timeoutSeconds: TimeInterval = 3.0) async {
        if !isReplicaSpeaking { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            stoppedContinuations.append((inferenceId, cont))
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                self.resumeStopped(inferenceId: inferenceId)
            }
        }
    }

    private func resumeStopped(inferenceId: String?) {
        stoppedContinuations.removeAll { entry in
            let (wid, cont) = entry
            if wid == inferenceId || wid == nil { cont.resume(); return true }
            return false
        }
    }

    func onReplicaStartedSpeaking(inferenceId: String?) { isReplicaSpeaking = true }
    func onReplicaStoppedSpeaking(inferenceId: String?, duration: Double?, interrupted: Bool) {
        isReplicaSpeaking = false
        resumeStopped(inferenceId: inferenceId)
    }
    func onUserStartedSpeaking() { isUserSpeaking = true }
    func onUserStoppedSpeaking() { isUserSpeaking = false }
}
