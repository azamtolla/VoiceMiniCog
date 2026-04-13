//
//  TavusService.swift
//  VoiceMiniCog
//
//  Manages Tavus CVI conversation lifecycle.
//  Creates conversations via Tavus API, returns Daily room URL for WebRTC embedding.
//

import Foundation
import SwiftUI

// MARK: - CLINICAL
// This service manages avatar-guided assessment sessions.
// No PHI is stored locally — all audio is processed ephemerally by Tavus.

@Observable
final class TavusService {
    // MARK: - Configuration

    static let shared = TavusService()

    /// Tavus API key — loaded from UserDefaults (configured in Settings)
    var apiKey: String {
        UserDefaults.standard.string(forKey: "tavus_api_key") ?? "ad59dab220804a8f81f07e21e78b5ba6"
    }

    /// Default persona for clinical assessment
    var personaId: String {
        UserDefaults.standard.string(forKey: "tavus_persona_id")
            ?? "pc64945f7e08" // Clinical Neuropsychologist persona
    }

    /// Default replica
    var replicaId: String {
        UserDefaults.standard.string(forKey: "tavus_replica_id")
            ?? "rf4e9d9790f0" // Anna - Professional
    }

    // MARK: - State

    var isCreatingConversation = false
    var activeConversation: TavusConversationSession?
    var lastError: String?
    private var preWarmTask: Task<Void, Never>?

    // MARK: - Pre-Warming

    /// Start creating a conversation in the background so it's ready when the
    /// clinician presses Start. Call this when the Home screen appears.
    func preWarm() {
        guard activeConversation == nil, !isCreatingConversation else { return }
        guard !apiKey.isEmpty else { return }

        preWarmTask = Task {
            do {
                _ = try await createConversation(
                    conversationName: "MercyCog Assessment \(Date().formatted(date: .abbreviated, time: .shortened))"
                )
                print("[Tavus] Pre-warm complete — conversation ready")
            } catch {
                // Non-fatal — we'll retry when Start is pressed
                print("[Tavus] Pre-warm failed (will retry on Start): \(error.localizedDescription)")
            }
        }
    }

    /// Cancel and clean up a pre-warmed conversation that was never used.
    func cancelPreWarm() {
        preWarmTask?.cancel()
        preWarmTask = nil
        if let conversation = activeConversation {
            let cid = conversation.conversation_id
            activeConversation = nil
            Task { await endConversation(cid) }
        }
        // Allow audio session to be reconfigured on next assessment start.
        AudioSessionManager.shared.resetConfiguration()
    }

    // MARK: - Conversation Lifecycle

    /// Creates a new Tavus conversation and returns the session with Daily room URL
    func createConversation(
        personaId: String? = nil,
        replicaId: String? = nil,
        conversationName: String? = nil
    ) async throws -> TavusConversationSession {
        let pid = personaId ?? self.personaId
        let rid = replicaId ?? self.replicaId

        guard !apiKey.isEmpty else {
            throw TavusError.missingAPIKey
        }

        await MainActor.run {
            isCreatingConversation = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isCreatingConversation = false
            }
        }

        // Build request body — disable recording and greenscreen to reduce
        // server-side pipeline latency and GPU overhead
        var body: [String: Any] = [
            "replica_id": rid,
            "persona_id": pid,
            "properties": [
                "enable_recording": false,
                "apply_greenscreen": false
            ]
        ]
        if let name = conversationName {
            body["conversation_name"] = name
        }

        // Tavus API call
        let url = URL(string: "https://tavusapi.com/v2/conversations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TavusError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TavusError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let session = try JSONDecoder().decode(TavusConversationSession.self, from: data)

        await MainActor.run {
            activeConversation = session
        }

        return session
    }

    /// Ends an active Tavus conversation
    func endConversation(_ conversationId: String? = nil) async {
        let cid = conversationId ?? activeConversation?.conversation_id
        guard let cid else { return }

        let url = URL(string: "https://tavusapi.com/v2/conversations/\(cid)/end")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try? await URLSession.shared.data(for: request)

        await MainActor.run {
            activeConversation = nil
        }
    }

    /// Checks if the API key is configured and valid
    func validateConfiguration() -> Bool {
        !apiKey.isEmpty
    }
}

// MARK: - Errors

enum TavusError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case conversationNotActive

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Tavus API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from avatar service."
        case .apiError(let code, _) where code == 429:
            return "Avatar service is busy. Please try again in a moment."
        case .apiError(let code, _) where code == 402:
            return "Avatar session limit reached. Please try again later."
        case .apiError(let code, _) where (500...599).contains(code):
            return "Avatar service is temporarily unavailable."
        case .apiError(let code, let message):
            return "Avatar connection failed (\(code)): \(message)"
        case .conversationNotActive:
            return "No active conversation."
        }
    }
}
