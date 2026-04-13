//
//  AudioSessionManager.swift
//  VoiceMiniCog
//
//  Configures AVAudioSession for bidirectional realtime voice conversation
//

import Foundation
import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    /// Configure audio session for simultaneous recording and playback
    /// suitable for realtime voice conversation (WebRTC)
    func configureForRealtimeVoice() throws {
        let session = AVAudioSession.sharedInstance()

        // Use voiceChat mode for bidirectional audio with echo cancellation
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP,
                .allowBluetoothA2DP
            ]
        )

        // Set preferred sample rate (OpenAI Realtime uses 24kHz)
        try session.setPreferredSampleRate(24000)

        // Set preferred buffer duration for low latency
        try session.setPreferredIOBufferDuration(0.01) // 10ms

        // Activate the session
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        print("[AudioSession] Configured for realtime voice: \(session.sampleRate)Hz")
    }

    /// Configure for playback only (used when transitioning away from realtime)
    func configureForPlaybackOnly() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )

        try session.setActive(true)

        print("[AudioSession] Configured for playback only")
    }

    /// Deactivate audio session
    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[AudioSession] Deactivated")
        } catch {
            print("[AudioSession] Failed to deactivate: \(error)")
        }
    }

    /// Check if microphone permission is granted
    func checkMicrophonePermission() async -> Bool {
        let status = AVAudioSession.sharedInstance().recordPermission

        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
