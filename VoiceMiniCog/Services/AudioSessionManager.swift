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

    /// True once configureForRealtimeVoice() has run successfully.
    /// Prevents repeated setCategory calls from triggering iOS
    /// beginInterruption on the already-active WebRTC session.
    /// Reset only on full session teardown (cancelPreWarm / app exit),
    /// NOT between assessment phases.
    private var isConfigured = false

    private init() {}

    /// Configure audio session for simultaneous recording and playback
    /// suitable for WebRTC (Tavus/Daily) + on-device ASR coexistence.
    /// Idempotent — no-ops after the first successful call.
    func configureForRealtimeVoice() throws {
        guard !isConfigured else {
            print("[AudioSession] Already configured, skipping")
            return
        }

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

        isConfigured = true
        print("[AudioSession] Configured for realtime voice: \(session.sampleRate)Hz")
    }

    /// Reset configuration state so the next configureForRealtimeVoice()
    /// call will actually configure. Call only when tearing down the
    /// entire WebRTC session (app exit, cancel pre-warm), not between phases.
    func resetConfiguration() {
        isConfigured = false
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
