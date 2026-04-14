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

    /// Tavus API key — loaded from Keychain (configured in Settings).
    /// Migrated from UserDefaults to Keychain for encrypted-at-rest storage.
    var apiKey: String = ""

    private static let keychainAPIKeyName = "tavus_api_key"

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

    /// UserDefaults key for persisting the pre-warmed conversation ID across
    /// app launches so orphaned conversations can be cleaned up on next start.
    private static let preWarmConversationKey = "tavus_prewarm_conversation_id"

    private static let voiceIsolationDefaultsKey = "tavus_voice_isolation"
    private static let voiceIsolationSyncedKey   = "tavus_voice_isolation_synced_key"
    private static let voiceIsolationSyncedAtKey = "tavus_voice_isolation_synced_at"
    /// Re-PATCH the persona if the sync cache is older than this interval,
    /// guarding against external edits (dashboard, other developer) that
    /// silently remove voice_isolation from the persona.
    private static let syncCacheTTL: TimeInterval = 6 * 3600 // 6 hours

    // MARK: - Init

    private init() {
        // Migration: move API key from UserDefaults (plaintext) to Keychain
        // (encrypted at rest). One-time on first launch after this update.
        if let legacyKey = UserDefaults.standard.string(forKey: "tavus_api_key"), !legacyKey.isEmpty {
            KeychainHelper.save(key: Self.keychainAPIKeyName, value: legacyKey)
            // Only remove from UserDefaults if Keychain read-back confirms the save succeeded.
            // Prevents silent key loss if SecItemAdd fails.
            if KeychainHelper.read(key: Self.keychainAPIKeyName) != nil {
                UserDefaults.standard.removeObject(forKey: "tavus_api_key")
            } else {
                print("[Tavus] ⚠️ Keychain migration failed — keeping key in UserDefaults as fallback")
            }
        }

        // Load API key: Keychain > environment variable > empty
        if let keychainKey = KeychainHelper.read(key: Self.keychainAPIKeyName), !keychainKey.isEmpty {
            apiKey = keychainKey
        } else if let envKey = ProcessInfo.processInfo.environment["TAVUS_API_KEY"], !envKey.isEmpty {
            apiKey = envKey
            KeychainHelper.save(key: Self.keychainAPIKeyName, value: envKey)
        } else {
            apiKey = ""
        }
        personaId = UserDefaults.standard.string(forKey: "tavus_persona_id") ?? "pc64945f7e08"
        replicaId = UserDefaults.standard.string(forKey: "tavus_replica_id") ?? "rf4e9d9790f0"

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // API key is now in Keychain; re-read it when defaults change
            // (Settings view writes to Keychain directly via KeychainHelper).
            self?.apiKey = KeychainHelper.read(key: Self.keychainAPIKeyName) ?? ""
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
    ///
    /// **Orphan cleanup:** On launch, if a previous session left a conversation
    /// ID in UserDefaults (e.g., app crashed or was force-quit before
    /// `cancelPreWarm` / `endConversation` could run), we end that orphaned
    /// conversation before creating a new one. This prevents server-side
    /// quota leaks.
    @MainActor
    func preWarm() {
        // B5 fix: guard on preWarmTask (set synchronously) rather than
        // isCreatingConversation (set asynchronously inside createConversation).
        guard preWarmTask == nil, activeConversation == nil else { return }
        guard !apiKey.isEmpty else { return }

        preWarmTask = Task {
            // Orphan cleanup: end any conversation left over from a prior session.
            if let orphanId = UserDefaults.standard.string(forKey: Self.preWarmConversationKey), !orphanId.isEmpty {
                UserDefaults.standard.removeObject(forKey: Self.preWarmConversationKey)
                print("[Tavus] Ending orphaned pre-warm conversation: \(orphanId)")
                await endConversation(orphanId)
            }

            do {
                let session = try await createConversation(
                    conversationName: Self.defaultConversationName()
                )
                // Persist the conversation ID so we can clean it up if the app
                // terminates before the conversation is properly ended.
                UserDefaults.standard.set(session.conversation_id, forKey: Self.preWarmConversationKey)
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

        // Clear the persisted pre-warm ID so it won't be treated as orphaned on next launch.
        UserDefaults.standard.removeObject(forKey: Self.preWarmConversationKey)

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

    /// Syncs the full `layers` block to the Tavus persona via JSON Patch:
    /// `conversational_flow` (voice_isolation, turn-taking, sparrow-1),
    /// `stt` (tavus-deepgram-medical + hotwords + diarization),
    /// `perception` (raven-1, log-only downstream).
    ///
    /// Cached via a single fingerprint that invalidates whenever any layer's
    /// config changes — re-patch all layers together for atomic state.
    func syncVoiceIsolationToPersonaIfNeeded(personaId: String? = nil) async {
        let pid = personaId ?? self.personaId
        guard !apiKey.isEmpty, !pid.isEmpty else { return }

        let flow = desiredConversationalFlow
        let stt = desiredSTTLayer
        let perception = desiredPerceptionLayer

        let combinedFingerprint = "\(flow.syncFingerprint)||\(stt.syncFingerprint)||\(perception.syncFingerprint)"
        let syncToken = "\(pid)|\(combinedFingerprint)"
        let storedToken = UserDefaults.standard.string(forKey: Self.voiceIsolationSyncedKey)

        if storedToken == syncToken {
            let syncedAt = UserDefaults.standard.double(forKey: Self.voiceIsolationSyncedAtKey)
            if syncedAt > 0, Date().timeIntervalSince1970 - syncedAt < Self.syncCacheTTL {
                return
            }
            print("[Tavus] persona sync cache expired (TTL) — re-patching all layers for \(pid)")
        }

        do {
            try await patchPersonaConversationalFlow(personaId: pid, flow: flow)
            try await patchPersonaSTTLayer(personaId: pid, stt: stt)
            try await patchPersonaPerceptionLayer(personaId: pid, perception: perception)
            UserDefaults.standard.set(syncToken, forKey: Self.voiceIsolationSyncedKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.voiceIsolationSyncedAtKey)
            await MainActor.run { voiceIsolationSyncFailed = false }
            print("[Tavus] Persona fully synced: \(pid)")
            print("       flow=\(flow.syncFingerprint)")
            print("       stt=\(stt.syncFingerprint)")
            print("       perception=\(perception.syncFingerprint)")
        } catch {
            await MainActor.run { voiceIsolationSyncFailed = true }
            print("[Tavus] ⚠️ persona layer sync FAILED — sessions may lack medical STT / diarization / noise isolation: \(error.localizedDescription)")
        }
    }

    /// Generic layer-PATCH helper — patch a single `layers.<name>` block,
    /// falling back to creating the block if it doesn't exist yet.
    private func patchPersonaLayer(
        personaId: String,
        layerName: String,
        orderedFields: [(key: String, value: Any)],
        asDictionary: [String: Any]
    ) async throws {
        var request = URLRequest(url: Self.personaURL(personaId))
        request.httpMethod = "PATCH"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let fieldOps: [[String: Any]] = orderedFields.map { key, value in
            ["op": "add", "path": "/layers/\(layerName)/\(key)", "value": value]
        }
        let attempts: [(label: String, body: [[String: Any]])] = [
            ("add fields to existing /layers/\(layerName)", fieldOps),
            ("add /layers/\(layerName) block",
             [["op": "add", "path": "/layers/\(layerName)", "value": asDictionary]])
        ]

        var lastMessage = ""
        for (idx, attempt) in attempts.enumerated() {
            request.httpBody = try JSONSerialization.data(withJSONObject: attempt.body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TavusError.invalidResponse
            }
            if (200...299).contains(http.statusCode) {
                print("[Tavus] PATCH /layers/\(layerName) succeeded via attempt \(idx + 1)/2 (\(attempt.label)) — HTTP \(http.statusCode)")
                return
            }
            if http.statusCode == 304 {
                print("[Tavus] ⚠️ PATCH /layers/\(layerName) returned 304 — treating as stale")
                return
            }
            lastMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            print("[Tavus] PATCH /layers/\(layerName) attempt \(idx + 1)/2 failed — HTTP \(http.statusCode): \(lastMessage.prefix(200))")
            if http.statusCode != 400 && http.statusCode != 422 {
                throw TavusError.apiError(statusCode: http.statusCode, message: lastMessage)
            }
        }
        throw TavusError.apiError(statusCode: 422, message: lastMessage)
    }

    private func patchPersonaSTTLayer(personaId: String, stt: STTLayerSettings) async throws {
        let ordered: [(key: String, value: Any)] = [
            ("stt_engine",   stt.engine),
            ("hotwords",     stt.hotwords.joined(separator: ", ")),
            ("diarization",  stt.diarization),
            ("smart_format", stt.smartFormat),
            ("language",     stt.language)
        ]
        try await patchPersonaLayer(
            personaId: personaId,
            layerName: "stt",
            orderedFields: ordered,
            asDictionary: stt.asDictionary
        )
    }

    private func patchPersonaPerceptionLayer(personaId: String, perception: PerceptionLayerSettings) async throws {
        let ordered: [(key: String, value: Any)] = [
            ("perception_model_name",   perception.modelName),
            ("ambient_awareness_queries", perception.ambientAwareness)
        ]
        try await patchPersonaLayer(
            personaId: personaId,
            layerName: "perception",
            orderedFields: ordered,
            asDictionary: perception.asDictionary
        )
    }

    /// Clears the last-applied sync token so the next `createConversation` or explicit sync
    /// will PATCH again.
    func invalidateVoiceIsolationSyncCache() {
        UserDefaults.standard.removeObject(forKey: Self.voiceIsolationSyncedKey)
        UserDefaults.standard.removeObject(forKey: Self.voiceIsolationSyncedAtKey)
    }

    // MARK: - Conversational Flow

    /// The full desired state for `layers.conversational_flow` on the persona.
    ///
    /// Clinical rationale:
    /// - `turn_taking_patience: "high"` — MCI patients speak slowly and hesitate.
    ///   "high" lets them finish a thought without the avatar cutting in.
    /// - `replica_interruptibility: "low"` — background noise (caregiver speaking,
    ///   exam-room sounds) should NOT cause the avatar to stop mid-sentence.
    ///   Swift-side DailyCallManager.handleUserStoppedSpeaking remains the
    ///   authoritative auto-interrupt source for genuine patient speech.
    /// - `sparrow-1` — Tavus audio-native turn-detection model. <600ms latency.
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

    // MARK: - Clinical STT Layer (Tavus Deepgram Medical)

    /// Clinical hotwords — surface these to Deepgram Medical so transcriptions
    /// of MCI-relevant vocabulary are less likely to be mis-recognized.
    /// Keep short and non-overlapping.
    private static let clinicalHotwords: [String] = [
        "MiniCog", "Mini-Cog", "QMCI", "QDRS", "AD8",
        "clock drawing", "word recall", "word registration",
        "verbal fluency", "story recall", "orientation",
        "delayed recall", "immediate recall", "animal naming"
    ]

    private struct STTLayerSettings {
        let engine: String        // e.g. "tavus-deepgram-medical"
        let hotwords: [String]
        let diarization: Bool
        let smartFormat: Bool
        let language: String      // "en-US" / "es-US" etc. (picked at session start)

        var asDictionary: [String: Any] {
            [
                "stt_engine":  engine,
                "hotwords":    hotwords.joined(separator: ", "),
                "diarization": diarization,
                "smart_format": smartFormat,
                "language":    language
            ]
        }

        var syncFingerprint: String {
            "\(engine)|\(diarization ? "d1" : "d0")|\(hotwords.joined(separator: ","))|\(language)"
        }
    }

    /// Desired STT layer. Medical engine + clinical hotwords + diarization
    /// enabled (essential for Family Caregiver mode so patient vs. caregiver
    /// speech is attributable).
    private var desiredSTTLayer: STTLayerSettings {
        STTLayerSettings(
            engine: "tavus-deepgram-medical",
            hotwords: Self.clinicalHotwords,
            diarization: true,
            smartFormat: true,
            language: preferredSTTLanguage
        )
    }

    /// Caller-selected STT language for the next session. Default en-US.
    /// Set via UserDefaults key `voiceMiniCog.stt_language` from MA handoff.
    private var preferredSTTLanguage: String {
        UserDefaults.standard.string(forKey: "voiceMiniCog.stt_language") ?? "en-US"
    }

    // MARK: - Perception Layer (raven-1, log-only)

    private struct PerceptionLayerSettings {
        let modelName: String     // "raven-1"
        let ambientAwareness: Bool

        var asDictionary: [String: Any] {
            [
                "perception_model_name": modelName,
                "ambient_awareness_queries": ambientAwareness
            ]
        }

        var syncFingerprint: String { "\(modelName)|aa:\(ambientAwareness ? 1 : 0)" }
    }

    /// Desired perception layer. raven-1 fuses audio + visual into unified
    /// behavioral understanding. CLINICAL CONSTRAINT: output is LOG-ONLY. It
    /// must NEVER alter avatar behavior mid-assessment or feed into scoring.
    /// See webhook handler for application.perception_analysis — stored as
    /// research log, never as a clinical signal.
    private var desiredPerceptionLayer: PerceptionLayerSettings {
        PerceptionLayerSettings(
            modelName: "raven-1",
            ambientAwareness: false  // Keep avatar focused; no ambient chatter.
        )
    }

    // MARK: - Persona System Prompt Guardrails

    /// Hardcoded guardrails appended to every persona system prompt. These
    /// encode non-negotiable clinical/regulatory behavioral constraints:
    /// - never diagnose
    /// - never interpret scores
    /// - complete all subtests in order
    /// - never correct, coach, or evaluate patient answers
    /// - voice is neutral and clinical, not casual
    static let personaGuardrails: String = """
    STRICT CLINICAL GUARDRAILS — NON-NEGOTIABLE:
    1. NEVER diagnose any condition. You are not a physician. Do not suggest,
       imply, or explicitly name any disease or condition, even if asked.
    2. NEVER interpret scores. Do not say whether a patient did well or poorly.
       Do not offer performance feedback of any kind ("good", "great", "not quite",
       "you got it", "close", "almost", etc.).
    3. Administer all subtests IN ORDER as instructed by the app. Do not skip,
       reorder, or invent steps. If confused about the current phase, remain silent.
    4. NEVER correct the patient's answers. The examiner does not confirm or deny
       correctness. Respond neutrally regardless of whether the answer is right or
       wrong.
    5. VOICE STYLE: calm, measured, professional. No slang, jokes, exclamation
       marks, or casual tone. Warm but clinical.
    6. If asked medical questions, respond: "That's a good question for your
       doctor." Do not elaborate.
    7. You are guided by echo commands. Do not ad-lib or generate free-form
       content during scripted subtest phases.
    """

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
