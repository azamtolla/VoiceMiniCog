//
//  SpeechService.swift
//  VoiceMiniCog
//
//  Handles speech recognition using SFSpeechRecognizer + AVAudioEngine
//

import Foundation
import Speech
import AVFoundation
import Combine

class SpeechService: ObservableObject {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    /// Retained as instance property so iOS doesn't deallocate it mid-utterance.
    private var synthesizer: AVSpeechSynthesizer?

    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var errorMessage: String? = nil

    // Authorization status
    @Published var isAuthorized: Bool = false

    // MARK: - Debug Fixture Mode

    /// When true (simulator only), `startListening()` injects a sample
    /// transcript after a short delay so phases that depend on ASR
    /// (orientation, verbal fluency, word recall) can be exercised
    /// without a physical microphone. Set via launch argument
    /// `-speechFixtures YES` or the SPEECH_FIXTURES env var.
    static var fixturesEnabled: Bool {
        #if targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: "speechFixtures") { return true }
        if ProcessInfo.processInfo.environment["SPEECH_FIXTURES"] != nil { return true }
        return false
        #else
        return false
        #endif
    }

    /// Fixture transcript to inject on the simulator. Callers can set this
    /// before calling `startListening()` to customize the simulated response.
    var fixtureTranscript: String?

    /// Work item for the delayed fixture injection (cancellable on stop).
    private var fixtureWork: DispatchWorkItem?

    // Check if running on simulator
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        if !isSimulator {
            audioEngine = AVAudioEngine()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }
                    switch status {
                    case .authorized:
                        self.isAuthorized = true
                        continuation.resume(returning: true)
                    case .denied, .restricted, .notDetermined:
                        self.isAuthorized = false
                        self.errorMessage = "Speech recognition not authorized"
                        continuation.resume(returning: false)
                    @unknown default:
                        self.isAuthorized = false
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - Start Listening

    func startListening() async throws {
        // Skip on simulator - no microphone available
        if isSimulator {
            print("[SpeechService] Running on simulator - speech recognition disabled")
            isListening = true
            transcript = ""

            // Debug fixture mode: inject a sample transcript after 1.5s so
            // downstream scorers and phase logic can be exercised on the
            // simulator without a real microphone.
            if Self.fixturesEnabled, let fixture = fixtureTranscript, !fixture.isEmpty {
                fixtureWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.isListening else { return }
                    self.transcript = fixture
                    print("[SpeechService] Fixture injected: \(fixture.prefix(60))...")
                }
                fixtureWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
            }
            return
        }

        // Reset any existing session
        stopListening()

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("[SpeechService] Speech recognizer not available")
            throw SpeechError.recognizerNotAvailable
        }

        // Recreate audio engine to avoid stale state
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw SpeechError.audioEngineNotAvailable
        }

        // Audio session is already configured by WebRTC (Daily SDK) at room
        // join via AudioSessionManager.configureForRealtimeVoice(). Do NOT
        // reconfigure here — calling setCategory or setActive mid-session
        // triggers iOS AudioSession::beginInterruption on the active WebRTC
        // session, permanently silencing avatar audio. SpeechService just
        // installs a tap on the existing audio engine input node.

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        // Get input node - wrap in do/catch for simulator safety
        do {
            let inputNode = audioEngine.inputNode

            // Get the native format - must check it's valid
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Validate format before installing tap
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("[SpeechService] Invalid recording format: \(recordingFormat)")
                throw SpeechError.audioEngineNotAvailable
            }

            // Install tap on input
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
            transcript = ""
        } catch {
            print("[SpeechService] Failed to start audio engine: \(error)")
            self.recognitionRequest = nil
            throw SpeechError.audioEngineNotAvailable
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.stopListening()
                }
            }

            if result?.isFinal == true {
                DispatchQueue.main.async {
                    self.stopListening()
                }
            }
        }
    }

    // MARK: - Stop Listening

    func stopListening() {
        // Cancel any pending fixture injection.
        fixtureWork?.cancel()
        fixtureWork = nil

        // Always clean up audio resources regardless of isListening flag.
        // Handles error paths where startListening() threw after installing
        // a tap but before setting isListening = true — without this, a
        // dangling tap leaks the audio session lock.
        if !isSimulator {
            recognitionTask?.cancel()
            recognitionTask = nil

            recognitionRequest?.endAudio()
            recognitionRequest = nil

            if let audioEngine = audioEngine, audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
        }

        isListening = false

        // Do NOT reconfigure the audio session here. WebRTC (Daily SDK)
        // owns the session for avatar playback. Switching to .playback mode
        // would evict WebRTC and silence the avatar for all subsequent speech.
        // The .playAndRecord + .voiceChat + .mixWithOthers configuration set
        // in startListening() is already compatible with WebRTC — just leave
        // the session as-is and let WebRTC continue using it.
    }

    // MARK: - Text-to-Speech (placeholder)
    // TODO: Implement actual TTS using AVSpeechSynthesizer or ElevenLabs

    func speak(_ text: String) async {
        // Synthesizer stored as instance property to prevent deallocation
        // mid-utterance (local vars are released at scope exit, silently
        // stopping playback in release builds).
        synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        await withCheckedContinuation { [weak self] continuation in
            // TODO: Use delegate for proper async handling
            self?.synthesizer?.speak(utterance)

            // Wait for estimated duration
            let duration = Double(text.count) * 0.06  // Rough estimate
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Errors

enum SpeechError: Error, LocalizedError {
    case recognizerNotAvailable
    case audioEngineNotAvailable
    case requestCreationFailed
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .audioEngineNotAvailable:
            return "Audio engine is not available"
        case .requestCreationFailed:
            return "Could not create recognition request"
        case .notAuthorized:
            return "Speech recognition not authorized"
        }
    }
}
