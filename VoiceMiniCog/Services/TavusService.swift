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

    /// Tavus API key — loaded from UserDefaults (configured in Settings).
    /// B1 fix: no compiled-in fallback; must be provided via Settings.
    var apiKey: String = ""

    /// Default persona for clinical assessment
    var personaId: String = ""

    /// Default replica
    var replicaId: String = ""

    /// Participant voice isolation (`layers.conversational_flow.voice_isolation` on the persona).
    /// Synced via PATCH before each conversation when the persona or setting changes.
    var voiceIsolation: TavusVoiceIsolation {
        let raw = UserDefaults.standard.string(forKey: Self.voiceIsolationDefaultsKey) ?? "near"
        return TavusVoiceIsolation(rawValue: raw) ?? .near
    }

    private static let voiceIsolationDefaultsKey = "tavus_voice_isolation"
    private static let voiceIsolationSyncedKey   = "tavus_voice_isolation_synced_key"
    private static let voiceIsolationSyncedAtKey = "tavus_voice_isolation_synced_at"
    /// Re-PATCH the persona if the sync cache is older than this interval,
    /// guarding against external edits (dashboard, other developer) that
    /// silently remove voice_isolation from the persona.
    private static let syncCacheTTL: TimeInterval = 6 * 3600 // 6 hours

    // MARK: - Init

    private init() {
        apiKey = UserDefaults.standard.string(forKey: "tavus_api_key") ?? ""
        personaId = UserDefaults.standard.string(forKey: "tavus_persona_id") ?? "pc64945f7e08"
        replicaId = UserDefaults.standard.string(forKey: "tavus_replica_id") ?? "rf4e9d9790f0"

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.apiKey = UserDefaults.standard.string(forKey: "tavus_api_key") ?? ""
            self?.personaId = UserDefaults.standard.string(forKey: "tavus_persona_id") ?? "pc64945f7e08"
            self?.replicaId = UserDefaults.standard.string(forKey: "tavus_replica_id") ?? "rf4e9d9790f0"
        }
    }

    deinit {
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Helpers

    /// Fixed-format conversation name used across pre-warm, start, and retry paths.
    /// Uses en_US_POSIX locale so the name is consistent regardless of device locale.
    static func defaultConversationName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return "MercyCog Assessment \(f.string(from: Date()))"
    }

    // MARK: - Static URL constants

    // B8 fix: single declaration point for API URLs.
    private static let conversationsURL = URL(string: "https://tavusapi.com/v2/conversations")!
    private static func conversationEndURL(_ id: String) -> URL {
        URL(string: "https://tavusapi.com/v2/conversations/\(id)/end")!
    }
    private static func personaURL(_ id: String) -> URL {
        URL(string: "https://tavusapi.com/v2/personas/\(id)")!
    }

    // MARK: - State

    var isCreatingConversation = false
    var activeConversation: TavusConversationSession?
    var lastError: String?
    /// True when the most recent voice_isolation PATCH failed — lets UI surface a warning.
    var voiceIsolationSyncFailed = false

    /// Stored observer token for UserDefaults change notifications.
    private var defaultsObserver: NSObjectProtocol?

    // B12 fix: preWarmTask must only be touched on MainActor because preWarm()
    // and cancelPreWarm() are called from UI / MainActor contexts.
    @MainActor private var preWarmTask: Task<Void, Never>?

    // MARK: - Pre-Warming

    /// Start creating a conversation in the background so it's ready when the
    /// clinician presses Start. Call this when the Home screen appears.
    @MainActor
    func preWarm() {
        // B5 fix: guard on preWarmTask (set synchronously) rather than
        // isCreatingConversation (set asynchronously inside createConversation).
        guard preWarmTask == nil, activeConversation == nil else { return }
        guard !apiKey.isEmpty else { return }

        preWarmTask = Task {
            do {
                _ = try await createConversation(
                    conversationName: Self.defaultConversationName()
                )
                print("[Tavus] Pre-warm complete — conversation ready")
            } catch {
                // Non-fatal — we'll retry when Start is pressed
                print("[Tavus] Pre-warm failed (will retry on Start): \(error.localizedDescription)")
            }
        }
    }

    /// Cancel and clean up a pre-warmed conversation that was never used.
    @MainActor
    func cancelPreWarm() {
        preWarmTask?.cancel()
        preWarmTask = nil

        // B3 fix: capture the conversation ID before clearing state, then end
        // it asynchronously. endConversation handles activeConversation = nil
        // only when IDs match (B4 fix).
        if let conversation = activeConversation {
            let cid = conversation.conversation_id
            activeConversation = nil
            Task { await endConversation(cid) }
        }
        // Allow audio session to be reconfigured on next assessment start.
        AudioSessionManager.shared.resetConfiguration()
    }

    // MARK: - Conversation Lifecycle

    /// Creates a new Tavus conversation and returns the session with Daily room URL.
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

        // B2 fix: explicit MainActor reset at every exit point instead of
        // defer { Task { @MainActor } } which was racey.
        do {
            // Don't block conversation creation on persona sync — it's non-fatal
            Task { await syncVoiceIsolationToPersonaIfNeeded(personaId: pid) }

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

            var request = URLRequest(url: Self.conversationsURL)
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
                isCreatingConversation = false
            }

            return session

        } catch {
            await MainActor.run {
                isCreatingConversation = false
                lastError = error.localizedDescription
            }
            throw error
        }
    }

    /// Syncs the full `layers.conversational_flow` block to the Tavus persona via JSON Patch.
    /// Includes voice_isolation (user-configurable), plus hardcoded clinical defaults for
    /// turn-taking patience, replica interruptibility, and VAD model.
    func syncVoiceIsolationToPersonaIfNeeded(personaId: String? = nil) async {
        let pid = personaId ?? self.personaId
        guard !apiKey.isEmpty, !pid.isEmpty else { return }

        let flow = desiredConversationalFlow
        let syncToken = "\(pid)|\(flow.syncFingerprint)"
        let storedToken = UserDefaults.standard.string(forKey: Self.voiceIsolationSyncedKey)

        // B7: UserDefaults reads/writes are thread-safe. @Observable derived
        // properties that read UserDefaults will see the updated value on the
        // next main-actor access.
        if storedToken == syncToken {
            let syncedAt = UserDefaults.standard.double(forKey: Self.voiceIsolationSyncedAtKey)
            if syncedAt > 0, Date().timeIntervalSince1970 - syncedAt < Self.syncCacheTTL {
                return
            }
            print("[Tavus] conversational_flow sync cache expired (TTL) — re-patching persona \(pid)")
        }

        do {
            try await patchPersonaConversationalFlow(personaId: pid, flow: flow)
            UserDefaults.standard.set(syncToken, forKey: Self.voiceIsolationSyncedKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.voiceIsolationSyncedAtKey)
            await MainActor.run { voiceIsolationSyncFailed = false }
            print("[Tavus] conversational_flow synced to persona \(pid): \(flow.syncFingerprint)")
        } catch {
            await MainActor.run { voiceIsolationSyncFailed = true }
            print("[Tavus] ⚠️ conversational_flow sync FAILED — sessions may lack noise isolation / turn-taking protection: \(error.localizedDescription)")
        }
    }

    /// Clears the last-applied sync token so the next `createConversation` or explicit sync
    /// will PATCH again.
    func invalidateVoiceIsolationSyncCache() {
        UserDefaults.standard.removeObject(forKey: Self.voiceIsolationSyncedKey)
        UserDefaults.standard.removeObject(forKey: Self.voiceIsolationSyncedAtKey)
    }

    // MARK: - Conversational Flow

    /// The full desired state for `layers.conversational_flow` on the persona.
    private var desiredConversationalFlow: ConversationalFlowSettings {
        ConversationalFlowSettings(
            voiceIsolation: voiceIsolation.rawValue,
            turnTakingPatience: "high",
            replicaInterruptibility: "low",
            turnDetectionModel: "sparrow-1"
        )
    }

    private struct ConversationalFlowSettings {
        let voiceIsolation: String
        let turnTakingPatience: String
        let replicaInterruptibility: String
        let turnDetectionModel: String

        var syncFingerprint: String {
            "\(voiceIsolation)|\(turnTakingPatience)|\(replicaInterruptibility)|\(turnDetectionModel)"
        }

        // B6 fix: explicitly ordered array so JSON Patch ops have deterministic order.
        var orderedFields: [(key: String, value: Any)] {
            [
                ("voice_isolation",          voiceIsolation),
                ("turn_taking_patience",     turnTakingPatience),
                ("replica_interruptibility", replicaInterruptibility),
                ("turn_detection_model",     turnDetectionModel)
            ]
        }

        var asDictionary: [String: Any] {
            Dictionary(uniqueKeysWithValues: orderedFields.map { ($0.key, $0.value) })
        }
    }

    private func patchPersonaConversationalFlow(personaId: String, flow: ConversationalFlowSettings) async throws {
        var request = URLRequest(url: Self.personaURL(personaId))
        request.httpMethod = "PATCH"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // B6 fix: iterate orderedFields (stable order) instead of asDictionary.map.
        let fieldOps: [[String: Any]] = flow.orderedFields.map { key, value in
            ["op": "add", "path": "/layers/conversational_flow/\(key)", "value": value]
        }

        let attempts: [(label: String, body: [[String: Any]])] = [
            ("add fields to existing layer", fieldOps),
            ("add /conversational_flow layer",
             [["op": "add", "path": "/layers/conversational_flow", "value": flow.asDictionary]])
        ]

        var lastMessage = ""
        for (idx, attempt) in attempts.enumerated() {
            request.httpBody = try JSONSerialization.data(withJSONObject: attempt.body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TavusError.invalidResponse
            }
            if (200...299).contains(http.statusCode) {
                print("[Tavus] PATCH conversational_flow succeeded via attempt \(idx + 1)/2 (\(attempt.label)) — HTTP \(http.statusCode)")
                return
            }
            // B10 fix: HTTP 304 on a PATCH is unexpected — log warning.
            if http.statusCode == 304 {
                print("[Tavus] ⚠️ PATCH returned 304 Not Modified — unexpected for PATCH; treating as stale. Will re-sync on next session.")
                return
            }
            lastMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            print("[Tavus] PATCH attempt \(idx + 1)/2 (\(attempt.label)) failed — HTTP \(http.statusCode): \(lastMessage.prefix(200))")
            if http.statusCode != 400 && http.statusCode != 422 {
                throw TavusError.apiError(statusCode: http.statusCode, message: lastMessage)
            }
        }
        throw TavusError.apiError(statusCode: 422, message: lastMessage)
    }

    /// Ends an active Tavus conversation.
    func endConversation(_ conversationId: String? = nil) async {
        let cid = conversationId ?? activeConversation?.conversation_id
        guard let cid else {
            print("[Tavus] endConversation: no conversation ID — possible orphaned server session")
            return
        }

        var request = URLRequest(url: Self.conversationEndURL(cid))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // B9 fix: short timeout for fire-and-forget teardown.
        request.timeoutInterval = 10

        if let (_, response) = try? await URLSession.shared.data(for: request) {
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                print("[Tavus] endConversation HTTP \(http.statusCode) for conversation \(cid)")
            }
        }

        await MainActor.run {
            // B4 fix: only nil activeConversation when the ended ID matches.
            if activeConversation?.conversation_id == cid {
                activeConversation = nil
            }
        }
    }

    /// Returns true when the API key, persona ID, and replica ID are all configured.
    // B11 fix: also checks personaId and replicaId.
    func validateConfiguration() -> Bool {
        !apiKey.isEmpty && !personaId.isEmpty && !replicaId.isEmpty
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
