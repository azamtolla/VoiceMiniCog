//
//  ElevenLabsService.swift
//  VoiceMiniCog
//
//  ElevenLabs Text-to-Speech integration matching React implementation
//

import Foundation
import AVFoundation

@Observable
class ElevenLabsService: NSObject {
    // Configuration - matching React defaults
    var apiKey: String = ""  // Set via settings or hardcode for testing
    var voiceId: String = "EXAVITQu4vr4xnSDxMaL"  // "Sarah" - calm, professional
    var modelId: String = "eleven_turbo_v2_5"

    // Voice settings matching React
    let stability: Double = 0.65
    let similarityBoost: Double = 0.75
    let style: Double = 0.15
    let useSpeakerBoost: Bool = true

    private var audioPlayer: AVAudioPlayer?
    private var completionHandler: (() -> Void)?

    var isSpeaking: Bool = false
    var errorMessage: String?

    override init() {
        super.init()
        setupAudioSession()
    }

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[ElevenLabs] Audio session setup failed: \(error)")
        }
    }

    // MARK: - Speak with ElevenLabs

    func speak(_ text: String) async {
        // Ensure audio session is configured for playback
        setupAudioSession()

        guard !apiKey.isEmpty else {
            print("[ElevenLabs] No API key - falling back to system TTS")
            await speakWithSystemTTS(text)
            return
        }

        isSpeaking = true
        errorMessage = nil

        do {
            let audioData = try await fetchAudio(for: text)
            try await playAudio(audioData)
        } catch {
            print("[ElevenLabs] Error: \(error). Falling back to system TTS")
            errorMessage = error.localizedDescription
            await speakWithSystemTTS(text)
        }

        isSpeaking = false
    }

    private func fetchAudio(for text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": stability,
                "similarity_boost": similarityBoost,
                "style": style,
                "use_speaker_boost": useSpeakerBoost
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw ElevenLabsError.apiError(statusCode: httpResponse.statusCode)
        }

        return data
    }

    private func playAudio(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.delegate = self
                completionHandler = {
                    continuation.resume()
                }
                audioPlayer?.play()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Fallback System TTS

    private var systemSynthesizer: AVSpeechSynthesizer?

    private func speakWithSystemTTS(_ text: String) async {
        isSpeaking = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let synthesizer = AVSpeechSynthesizer()
            systemSynthesizer = synthesizer

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

            synthesizer.speak(utterance)

            // Wait for estimated duration
            let words = text.split(separator: " ").count
            let duration = Double(words) * 0.4 + 0.5

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                continuation.resume()
            }
        }

        isSpeaking = false
    }

    // MARK: - Speak Words Slowly (for word registration)

    func speakWordsSlowly(_ words: [String], prefix: String? = nil) async {
        if let prefix = prefix {
            await speak(prefix)
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms pause
        }

        for (index, word) in words.enumerated() {
            await speak(word)
            if index < words.count - 1 {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s pause between words
            }
        }
    }

    func stop() {
        audioPlayer?.stop()
        isSpeaking = false
    }
}

// MARK: - AVAudioPlayerDelegate

extension ElevenLabsService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completionHandler?()
        completionHandler = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        completionHandler?()
        completionHandler = nil
    }
}

// MARK: - Errors

enum ElevenLabsError: Error, LocalizedError {
    case noApiKey
    case invalidResponse
    case apiError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "ElevenLabs API key not configured"
        case .invalidResponse:
            return "Invalid response from ElevenLabs"
        case .apiError(let code):
            return "ElevenLabs API error: \(code)"
        }
    }
}
