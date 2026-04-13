//
//  SpeechService.swift
//  VoiceMiniCog
//
//  Handles speech recognition using SFSpeechRecognizer + AVAudioEngine
//

import Foundation
import Speech
import AVFoundation

@Observable
class SpeechService {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    var transcript: String = ""
    var isListening: Bool = false
    var errorMessage: String? = nil

    // Authorization status
    var isAuthorized: Bool = false

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
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
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

        do {
            // Configure audio session for recording — must coexist with WebRTC.
            // .voiceChat mode is compatible with Daily's WebRTC audio session
            // and enables built-in echo cancellation (filters avatar speaker
            // output from the mic input). .mixWithOthers allows SpeechService
            // and WebRTC to share the session without evicting each other.
            // Previously used .measurement mode which silently interrupted
            // WebRTC's playback, causing avatar audio to go silent.
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SpeechService] Audio session setup failed: \(error)")
            throw SpeechError.audioEngineNotAvailable
        }

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
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
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
        guard isListening else { return }

        // On simulator, just reset the flag
        if isSimulator {
            isListening = false
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let audioEngine = audioEngine, audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
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
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        await withCheckedContinuation { continuation in
            // Simple synchronous speak for now
            // TODO: Use delegate for proper async handling
            synthesizer.speak(utterance)

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
