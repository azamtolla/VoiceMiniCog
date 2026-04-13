//
//  AudioSessionManager.swift
//  VoiceMiniCog
//
//  Single source of truth for AVAudioSession configuration.
//  Tavus CVI uses Daily.co WebRTC for bidirectional avatar audio.
//  SpeechService (on-device ASR) shares the same session via .mixWithOthers.
//

import Foundation
import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {}

    /// Configure audio session for simultaneous recording and playback
    /// suitable for WebRTC (Tavus/Daily) + on-device ASR coexistence.
    func configureForRealtimeVoice() throws {
        let session = AVAudioSession.sharedInstance()

        // .voiceChat: bidirectional audio with built-in echo cancellation.
        // .mixWithOthers: allows WebRTC and SpeechService to share the
        // session without evicting each other — without this flag,
        // whichever subsystem calls setCategory last wins exclusive
        // ownership and silences the other.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [
                .defaultToSpeaker,
                .allowBluetoothHFP,
                .allowBluetoothA2DP,
                .mixWithOthers
            ]
        )

        // Let iOS negotiate sample rate and buffer duration with Daily's
        // WebRTC stack. Forcing 24kHz or 10ms buffers can cause resampling
        // artifacts or audio starvation on older devices.

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
        let status = AVAudioApplication.shared.recordPermission

        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
