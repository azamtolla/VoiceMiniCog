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

    // MARK: - Voice-mode patient-speaking bridge (Task 4B)
    //
    // Phase views advance on .patientStartedSpeaking → .patientDoneSpeaking
    // (QAPhaseView.swift:78-88). In avatar mode Tavus/Daily post those; in
    // voice mode NOTHING does, so every orientation question would fall
    // through to the 10 s no-response timeout. This bridge posts them from
    // on-device ASR activity — ADDITIVE ONLY: transcript delivery to phase
    // views and scorers is untouched.

    /// Which guide mode the bridge consults before posting. Injectable so
    /// tests are deterministic regardless of Keychain/UserDefaults state;
    /// production default resolves live so a Settings change takes effect.
    var guideModeProvider: () -> GuideMode = { GuideMode.current }

    /// Trailing-partial absorber: SFSpeechRecognizer partials trail the
    /// audio by ~100-500 ms, so a transcription of the guide's own speech
    /// can arrive AFTER .avatarDoneSpeaking clears `guideIsSpeaking`.
    /// Partials within this interval of guide-speech end are still treated
    /// as self-hearing. Cost of a too-long value is only a slightly late
    /// .patientStartedSpeaking (the patient's next partial posts it);
    /// cost of a too-short value is a false started that cancels the
    /// silence watchdog. Tune on device.
    var bridgeGraceAfterGuideSpeech: TimeInterval = 0.4

    /// One listening window's bridge lifecycle. `.finalized` is distinct
    /// from `.idle` so a stray partial arriving after finalization (queued
    /// recognizer callback racing stopListening) cannot re-post started;
    /// only startListening() reopens the window.
    private enum BridgeWindowState { case idle, started, finalized }
    private var bridgeWindowState: BridgeWindowState = .idle

    /// Half-duplex gate: true while VoiceGuideService (or the avatar) is
    /// speaking. ASR activity during guide speech is the app hearing itself
    /// — never patient speech.
    private var guideIsSpeaking = false
    private var guideSpeechEndedAt: Date?
    private var bridgeObservers: [NSObjectProtocol] = []

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        if !isSimulator {
            audioEngine = AVAudioEngine()
        }
        // Half-duplex gate: track guide speech via the same seam
        // VoiceGuideService posts on. queue: .main + main-thread posting ⇒
        // synchronous delivery, so the flag is set before the guide's audio
        // can produce a partial.
        let nc = NotificationCenter.default
        bridgeObservers = [
            nc.addObserver(forName: .avatarStartedSpeaking, object: nil, queue: .main) { [weak self] _ in
                self?.guideIsSpeaking = true
            },
            nc.addObserver(forName: .avatarDoneSpeaking, object: nil, queue: .main) { [weak self] _ in
                self?.guideIsSpeaking = false
                self?.guideSpeechEndedAt = Date()
            },
        ]
    }

    deinit {
        bridgeObservers.forEach(NotificationCenter.default.removeObserver(_:))
    }

    /// First non-empty partial of a window posts .patientStartedSpeaking —
    /// once, and only in voice mode (avatar mode: Daily owns these posts;
    /// double-posting would double-advance QAPhaseView), and never while
    /// (or just after) the guide itself is speaking.
    private func bridgePartialTranscript(_ text: String) {
        guard guideModeProvider() == .voice else { return }
        guard bridgeWindowState == .idle else { return }
        guard !guideIsSpeaking else { return }
        if let ended = guideSpeechEndedAt,
           Date().timeIntervalSince(ended) < bridgeGraceAfterGuideSpeech {
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        bridgeWindowState = .started
        NotificationCenter.default.post(name: .patientStartedSpeaking, object: nil)
    }

    /// Window closed (final result, manual stop, or error path): post
    /// .patientDoneSpeaking iff started was posted. .started is only
    /// reachable in voice mode, so this is inherently mode-gated.
    private func bridgeFinalizeWindow() {
        guard bridgeWindowState == .started else { return }
        bridgeWindowState = .finalized
        NotificationCenter.default.post(name: .patientDoneSpeaking, object: nil)
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
        // Fresh answer window: drop any unfinalized bridge state WITHOUT
        // posting — a stale .patientDoneSpeaking at window-open could
        // falsely advance the phase view that just started listening.
        // (The stopListening() below therefore sees .idle and posts nothing.)
        bridgeWindowState = .idle

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
                    // Bridge the fixture like a complete utterance so
                    // voice-mode phase pacing is exercisable on the
                    // simulator (mode-gated inside; listening state and
                    // transcript delivery unchanged).
                    self.bridgePartialTranscript(fixture)
                    self.bridgeFinalizeWindow()
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
                    // Task 4B bridge — additive; transcript delivery above
                    // is unchanged. A final result also passes through here
                    // before the stop path below, so a single-shot final
                    // still produces started → done.
                    self.bridgePartialTranscript(result.bestTranscription.formattedString)
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

        // Task 4B bridge: closing a window in which patient speech was
        // heard posts .patientDoneSpeaking — covers isFinal (recognizer
        // callback calls stopListening), phase-view manual stops, and the
        // error path. No-ops unless started was posted for this window.
        bridgeFinalizeWindow()

        // Do NOT reconfigure the audio session here. WebRTC (Daily SDK)
        // owns the session for avatar playback. Switching to .playback mode
        // would evict WebRTC and silence the avatar for all subsequent speech.
        // The .playAndRecord + .voiceChat + .mixWithOthers configuration set
        // in startListening() is already compatible with WebRTC — just leave
        // the session as-is and let WebRTC continue using it.
    }

    // MARK: - Bridge test hooks (Task 4B)

    #if DEBUG
    /// Mirrors the recognizer's partial-result callback exactly:
    /// transcript set, then the bridge partial path.
    func simulatePartialTranscriptForTesting(_ text: String) {
        transcript = text
        bridgePartialTranscript(text)
    }

    /// Mirrors a final result exactly: the real callback runs a final
    /// result through the partial branch (transcript + bridge partial),
    /// then calls stopListening(), which finalizes the bridge window.
    func simulateFinalTranscriptForTesting(_ text: String) {
        transcript = text
        bridgePartialTranscript(text)
        stopListening()
    }
    #endif

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
