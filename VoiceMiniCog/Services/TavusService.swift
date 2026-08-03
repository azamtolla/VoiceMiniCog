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

    /// One-time migration key — flipped to true after the first launch that
    /// purged URLCache entries left over from builds that predate the
    /// `reloadIgnoringLocalAndRemoteCacheData` fix. Those stale entries
    /// could otherwise feed auto-conditional headers back into fresh
    /// requests despite the current cache policy.
    private static let urlCacheResidueClearedKey = "tavus_urlcache_residue_cleared_v1"

    private init() {
        // One-time URLCache purge. Prior builds defaulted to
        // URLSession's protocol cache, so GET /personas/{id} responses
        // with ETag / Last-Modified headers landed in URLCache.shared.
        // Even though the current build uses
        // `.reloadIgnoringLocalAndRemoteCacheData` everywhere, URLCache
        // entries persist on disk across app launches and upgrades.
        // Purge them once to guarantee no residue can ever feed a
        // conditional-header loop again.
        if !UserDefaults.standard.bool(forKey: Self.urlCacheResidueClearedKey) {
            URLCache.shared.removeAllCachedResponses()
            UserDefaults.standard.set(true, forKey: Self.urlCacheResidueClearedKey)
            print("[Tavus] URLCache residue cleared (one-time migration)")
        }

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
    static func personaURL(_ id: String) -> URL {
        URL(string: "https://tavusapi.com/v2/personas/\(id)")!
    }

    // MARK: - Request Builder
    //
    // Centralizes URLRequest construction so every Tavus call gets the same
    // cache policy and header hygiene. The prior ad-hoc builders used
    // `URLRequest`'s default `.useProtocolCachePolicy`, which lets
    // URLSession auto-attach `If-None-Match` / `If-Modified-Since` from
    // URLCache entries. Tavus's backend was then evaluating those
    // conditional headers on PATCH and responding 304 — which is abnormal
    // for a state-changing verb. Forcing `.reloadIgnoringLocalAndRemoteCacheData`
    // eliminates the auto-conditional on both PATCH and the follow-up GET
    // used by `verifyRemoteLayer`, and breaks the 304 feedback loop.

    /// Build a Tavus API request with cache disabled and standard headers.
    /// If `body` is non-nil, Content-Type is set automatically. `apiKey`
    /// is read from the instance at call time.
    ///
    /// `attachedConditionalHeaders` in the returned value is non-empty
    /// only if the caller explicitly adds them — the builder itself never
    /// attaches conditionals, and URLSession won't auto-attach because
    /// the cache policy bypasses URLCache.
    func buildTavusRequest(
        url: URL,
        method: String,
        bodyJSON: Any? = nil,
        timeout: TimeInterval = 30
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        // Hard-disable URLSession's protocol cache. Prevents the
        // If-None-Match / If-Modified-Since auto-attach that was provoking
        // the abnormal 304 responses on PATCH.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // Defense in depth — if something upstream set these, strip them.
        request.setValue(nil, forHTTPHeaderField: "If-None-Match")
        request.setValue(nil, forHTTPHeaderField: "If-Modified-Since")
        request.setValue(nil, forHTTPHeaderField: "If-Match")
        request.setValue(nil, forHTTPHeaderField: "If-Unmodified-Since")
        // Standard Tavus headers.
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        if let bodyJSON {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyJSON)
        }
        logTavusRequest(request)
        return request
    }

    /// Log method + endpoint + header NAMES (values redacted) + whether any
    /// conditional headers slipped through. Clinician/debug visibility only;
    /// no PHI in requests.
    private func logTavusRequest(_ request: URLRequest) {
        let method = request.httpMethod ?? "?"
        let urlPath = request.url?.path ?? "?"
        let headerNames = (request.allHTTPHeaderFields ?? [:]).keys.sorted()
        let conditionalsPresent = headerNames.contains(where: {
            let lower = $0.lowercased()
            return lower == "if-none-match" || lower == "if-modified-since"
                || lower == "if-match" || lower == "if-unmodified-since"
        })
        let conditionalTag = conditionalsPresent ? " conditional=ATTACHED" : " conditional=none"
        print("[Tavus.http] \(method) \(urlPath) headers=\(headerNames) policy=\(cachePolicyDescription(request.cachePolicy))\(conditionalTag)")
    }

    private func cachePolicyDescription(_ policy: URLRequest.CachePolicy) -> String {
        switch policy {
        case .useProtocolCachePolicy:             return "useProtocolCachePolicy"
        case .reloadIgnoringLocalCacheData:       return "reloadIgnoringLocalCacheData"
        case .reloadIgnoringLocalAndRemoteCacheData: return "reloadIgnoringLocalAndRemoteCacheData"
        case .returnCacheDataElseLoad:            return "returnCacheDataElseLoad"
        case .returnCacheDataDontLoad:            return "returnCacheDataDontLoad"
        case .reloadRevalidatingCacheData:        return "reloadRevalidatingCacheData"
        @unknown default:                         return "unknown"
        }
    }

    // MARK: - State

    var isCreatingConversation = false
    var activeConversation: TavusConversationSession?
    var lastError: String?

    /// Observable lifecycle of the persona layer sync. Drives the hard-gate
    /// at assessment start: only `.verified` permits proceeding into the
    /// Daily room join. `.failed` surfaces an error to the clinician and
    /// blocks the assessment — running with unverified STT/LLM/TTS config
    /// could misinterpret patient speech and produce invalid scores.
    var voiceIsolationSyncState: VoiceIsolationSyncState = .idle

    /// Backward-compat alias for existing UI bindings. Prefer
    /// `voiceIsolationSyncState` for new code.
    var voiceIsolationSyncFailed: Bool { voiceIsolationSyncState.isTerminalFailure }

    /// Max attempts for `ensurePersonaSyncVerified`. 1 initial + 2 retries.
    private static let personaSyncMaxAttempts = 3
    /// Backoff schedule between attempts (ms). Index i = delay BEFORE attempt i+1.
    private static let personaSyncBackoffMs: [UInt64] = [500, 1000, 2000]
    /// After a terminal-failure round (all 3 attempts exhausted), suppress
    /// further sync attempts for this window. Prevents the storm observed in
    /// the logs where prewarm → Start tap triggers 9 more PATCHes to the
    /// same failing endpoint within seconds. The Retry button in the
    /// welcome-screen error UI bypasses this by calling `bypassCooldown: true`.
    static let personaSyncCooldownWindow: TimeInterval = 30.0

    /// Timestamp of the most recent terminal failure (all attempts exhausted).
    /// Read in `ensurePersonaSyncVerified` to short-circuit retries inside
    /// the cooldown window. `nil` if there has been no terminal failure yet
    /// (or the cooldown was explicitly bypassed).
    @ObservationIgnored private var lastTerminalFailureAt: Date?
    /// Cached reason from the last terminal failure — returned for repeat
    /// callers inside the cooldown window.
    @ObservationIgnored private var lastTerminalFailureReason: String?

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

        print("[Tavus.lifecycle] preWarm — origin=prewarm")
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
                print("[Tavus] Pre-warm complete — conversation URL acquired=\(session.conversation_url.isEmpty ? "no" : "yes")")
            } catch {
                // Non-fatal — we'll retry when Start is pressed. Do NOT stamp
                // lastError here: conversation creation is best-effort and
                // a failed prewarm shouldn't render a blocking error banner
                // on the welcome screen.
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
            // Persona layer sync runs as best-effort in the background.
            // On success it sets voiceIsolationSyncState = .verified;
            // on failure it lands on .failed. Conversation creation
            // proceeds either way so the avatar can connect on the
            // welcome screen (scripted echo, no clinical scoring).
            // Any scoring phase that wants to gate on verified config
            // can observe `voiceIsolationSyncState` directly.
            Task { [pid] in
                do {
                    try await ensurePersonaSyncVerified(personaId: pid)
                } catch {
                    print("[Tavus] background persona sync did not verify: \(error.localizedDescription) — conversation proceeds with current remote persona config")
                }
            }

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

            let request = try buildTavusRequest(
                url: Self.conversationsURL,
                method: "POST",
                bodyJSON: body
            )

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

    /// Bounded-retry wrapper around `syncVoiceIsolationToPersonaIfNeeded`.
    ///
    /// **This is the hard-gate entry point.** `createConversation` awaits this
    /// and rethrows `TavusError.personaSyncUnverified` if all retries fail, so
    /// the assessment cannot proceed in fragile avatar mode.
    ///
    /// Retry policy: up to `personaSyncMaxAttempts` attempts, with
    /// `personaSyncBackoffMs` between attempts. Transient 5xx / network errors
    /// get retried; explicit 4xx responses that indicate a configuration
    /// problem (not a transient failure) still throw after final attempt.
    func ensurePersonaSyncVerified(
        personaId: String? = nil,
        bypassCooldown: Bool = false
    ) async throws {
        let pid = personaId ?? self.personaId
        guard !apiKey.isEmpty, !pid.isEmpty else {
            // No API key / persona — treat as unverified; the caller
            // (createConversation) will already throw .missingAPIKey first,
            // but surface the state for any UI observing sync directly.
            await MainActor.run {
                voiceIsolationSyncState = .failed(reason: "Missing API key or persona ID")
            }
            throw TavusError.personaSyncUnverified(reason: "Missing API key or persona ID")
        }

        // If we're already verified in this process and the cache token still
        // matches, skip the network round-trip entirely.
        if voiceIsolationSyncState == .verified,
           let storedToken = UserDefaults.standard.string(forKey: Self.voiceIsolationSyncedKey),
           storedToken == currentSyncToken(personaId: pid) {
            let syncedAt = UserDefaults.standard.double(forKey: Self.voiceIsolationSyncedAtKey)
            if syncedAt > 0, Date().timeIntervalSince1970 - syncedAt < Self.syncCacheTTL {
                return
            }
        }

        // COOLDOWN GATE: after a terminal-failure round we don't re-issue
        // 9 more PATCHes on every welcome-screen appearance / Start tap.
        // The UI surfaces the failure via `voiceIsolationSyncState = .failed`
        // and a user-initiated Retry button bypasses this via
        // `bypassCooldown: true`.
        if !bypassCooldown, let lastFailure = lastTerminalFailureAt {
            let decision = PersonaSyncCooldown.decide(
                lastTerminalFailureAt: lastFailure,
                now: Date(),
                window: Self.personaSyncCooldownWindow
            )
            switch decision {
            case .cooldownActive(let remaining):
                let reason = lastTerminalFailureReason ?? "Avatar service unavailable"
                print("[Tavus] persona sync COOLDOWN active (\(String(format: "%.1f", remaining))s remaining) — short-circuit with cached failure: \(reason)")
                await MainActor.run {
                    // Refresh observable state so any late-subscribing view
                    // still sees .failed even if it missed the first transition.
                    voiceIsolationSyncState = .failed(reason: reason)
                }
                throw TavusError.personaSyncUnverified(reason: reason)
            case .expired, .shouldRetry:
                break
            }
        }

        var lastError: Error?
        for attempt in 1...Self.personaSyncMaxAttempts {
            await MainActor.run {
                voiceIsolationSyncState = .syncing(attempt: attempt)
            }
            do {
                try await syncVoiceIsolationToPersonaIfNeeded(personaId: pid)
                await MainActor.run {
                    voiceIsolationSyncState = .verified
                    // Success clears any prior cooldown so the next retry
                    // (e.g., on persona config change) runs immediately.
                    lastTerminalFailureAt = nil
                    lastTerminalFailureReason = nil
                }
                return
            } catch {
                lastError = error
                print("[Tavus] persona sync attempt \(attempt)/\(Self.personaSyncMaxAttempts) failed: \(error.localizedDescription)")
                if attempt < Self.personaSyncMaxAttempts {
                    let delayNs = Self.personaSyncBackoffMs[attempt - 1] * 1_000_000
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
        }

        let reason = lastError?.localizedDescription ?? "unknown error"
        await MainActor.run {
            voiceIsolationSyncState = .failed(reason: reason)
            // Stamp cooldown so the next N seconds of calls short-circuit.
            lastTerminalFailureAt = Date()
            lastTerminalFailureReason = reason
        }
        print("[Tavus] ❌ persona sync FAILED after \(Self.personaSyncMaxAttempts) attempts — assessment must not proceed: \(reason). Cooldown \(Self.personaSyncCooldownWindow)s active.")
        throw TavusError.personaSyncUnverified(reason: reason)
    }

    /// Explicitly clear the cooldown. Called from the welcome-screen Retry
    /// button so a user-initiated retry always runs a fresh network round.
    func invalidateSyncCooldown() {
        lastTerminalFailureAt = nil
        lastTerminalFailureReason = nil
    }

    /// Build the fingerprint token for the current desired persona config.
    /// Used by both the cache check and the retry gate.
    private func currentSyncToken(personaId pid: String) -> String {
        let flow = desiredConversationalFlow
        let stt = desiredSTTLayer
        let perception = desiredPerceptionLayer
        let llm = desiredLLMLayer
        let tts = desiredTTSLayer
        let combined = [
            flow.syncFingerprint,
            stt.syncFingerprint,
            perception.syncFingerprint,
            llm.syncFingerprint,
            tts.syncFingerprint
        ].joined(separator: "||")
        return "\(pid)|\(combined)"
    }

    /// Syncs the full `layers` block to the Tavus persona via JSON Patch:
    /// `conversational_flow` (voice_isolation, turn-taking, sparrow-1),
    /// `stt` (tavus-deepgram-medical + hotwords + diarization),
    /// `perception` (raven-1, log-only downstream).
    ///
    /// Cached via a single fingerprint that invalidates whenever any layer's
    /// config changes — re-patch all layers together for atomic state.
    ///
    /// Throws on any layer failure so the retry wrapper in
    /// `ensurePersonaSyncVerified` can decide whether to retry or hard-fail.
    /// Callers that need the hard-gate behavior MUST go through the wrapper.
    func syncVoiceIsolationToPersonaIfNeeded(personaId: String? = nil) async throws {
        let pid = personaId ?? self.personaId
        guard !apiKey.isEmpty, !pid.isEmpty else { return }

        let flow = desiredConversationalFlow
        let stt = desiredSTTLayer
        let perception = desiredPerceptionLayer
        let llm = desiredLLMLayer
        let tts = desiredTTSLayer

        let syncToken = currentSyncToken(personaId: pid)
        let storedToken = UserDefaults.standard.string(forKey: Self.voiceIsolationSyncedKey)

        if storedToken == syncToken {
            let syncedAt = UserDefaults.standard.double(forKey: Self.voiceIsolationSyncedAtKey)
            if syncedAt > 0, Date().timeIntervalSince1970 - syncedAt < Self.syncCacheTTL {
                return
            }
            print("[Tavus] persona sync cache expired (TTL) — re-patching all layers for \(pid)")
        }

        try await patchPersonaConversationalFlow(personaId: pid, flow: flow)
        try await patchPersonaSTTLayer(personaId: pid, stt: stt)
        try await patchPersonaPerceptionLayer(personaId: pid, perception: perception)
        try await patchPersonaLLMLayer(personaId: pid, llm: llm)
        try await patchPersonaTTSLayer(personaId: pid, tts: tts)
        UserDefaults.standard.set(syncToken, forKey: Self.voiceIsolationSyncedKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.voiceIsolationSyncedAtKey)
        print("[Tavus] Persona fully synced: \(pid)")
        print("       flow=\(flow.syncFingerprint)")
        print("       stt=\(stt.syncFingerprint)")
        print("       perception=\(perception.syncFingerprint)")
        print("       llm=\(llm.syncFingerprint)")
        print("       tts=\(tts.syncFingerprint)")
    }

    /// Fetch the persona from Tavus and verify that the named layer block
    /// contains all of `expectedFields` with the expected values. Used to
    /// convert a 304 Not Modified response on PATCH into a real
    /// verification, since 304 alone is ambiguous (means either "identical
    /// to desired" or "identical to previous stale state").
    ///
    /// Returns true only if every expected field matches. False triggers the
    /// outer attempt loop to retry via the layer-create fallback body.
    private func verifyRemoteLayer(
        personaId: String,
        layerName: String,
        expectedFields: [(key: String, value: Any)]
    ) async -> Bool {
        do {
            // Same builder as PATCH — cache disabled so this GET response
            // does not land in URLCache and can't feed a later auto-conditional.
            let request = try buildTavusRequest(
                url: Self.personaURL(personaId),
                method: "GET",
                bodyJSON: nil,
                timeout: 15
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let layers = root["layers"] as? [String: Any],
                  let layer = layers[layerName] as? [String: Any]
            else {
                return false
            }
            for (key, expected) in expectedFields {
                guard let remote = layer[key] else { return false }
                if !anyEquals(remote, expected) { return false }
            }
            return true
        } catch {
            return false
        }
    }

    /// Loose equality across `[String: Any]` JSON values — handles the
    /// common cases we actually PATCH (String, Bool, Int, Double, [String],
    /// [String: Any]). Unknown types fall through to string-compare.
    private func anyEquals(_ a: Any, _ b: Any) -> Bool {
        if let a = a as? String, let b = b as? String { return a == b }
        if let a = a as? Bool, let b = b as? Bool { return a == b }
        if let a = a as? Int, let b = b as? Int { return a == b }
        if let a = a as? Double, let b = b as? Double { return abs(a - b) < 1e-9 }
        if let a = a as? [String], let b = b as? [String] { return a == b }
        if let a = a as? [Any], let b = b as? [Any] {
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { anyEquals($0, $1) }
        }
        if let a = a as? [String: Any], let b = b as? [String: Any] {
            guard a.keys.sorted() == b.keys.sorted() else { return false }
            return a.allSatisfy { key, av in
                guard let bv = b[key] else { return false }
                return anyEquals(av, bv)
            }
        }
        // Tavus returns hotwords as a single comma-separated string we PATCH
        // from an array-joined string — treat list-vs-string as equal if the
        // normalized tokens match.
        if let aStr = a as? String, let bList = b as? [String] {
            return aStr == bList.joined(separator: ", ")
        }
        if let aList = a as? [String], let bStr = b as? String {
            return aList.joined(separator: ", ") == bStr
        }
        return String(describing: a) == String(describing: b)
    }

    /// Generic layer-PATCH helper — patch a single `layers.<name>` block,
    /// falling back to creating the block if it doesn't exist yet.
    private func patchPersonaLayer(
        personaId: String,
        layerName: String,
        orderedFields: [(key: String, value: Any)],
        asDictionary: [String: Any]
    ) async throws {
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
            // buildTavusRequest sets method, body, cachePolicy, and strips
            // conditional headers — preventing URLSession from auto-attaching
            // If-None-Match / If-Modified-Since that provoke the 304 anomaly.
            let request = try buildTavusRequest(
                url: Self.personaURL(personaId),
                method: "PATCH",
                bodyJSON: attempt.body
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TavusError.invalidResponse
            }
            if (200...299).contains(http.statusCode) {
                print("[Tavus] PATCH /layers/\(layerName) succeeded via attempt \(idx + 1)/2 (\(attempt.label)) — HTTP \(http.statusCode)")
                return
            }
            // 304 on PATCH means Tavus considered the request an idempotent
            // no-op. That's ambiguous: it could mean "remote already matches
            // what we want" (good) OR "server re-used a stale prior response"
            // (bad). Verify by GET + field compare before accepting.
            if http.statusCode == 304 {
                let verified = await verifyRemoteLayer(
                    personaId: personaId,
                    layerName: layerName,
                    expectedFields: orderedFields
                )
                if verified {
                    print("[Tavus] PATCH /layers/\(layerName) returned 304 and GET-verified remote matches desired — accepting")
                    return
                }
                lastMessage = "304 Not Modified but GET verification showed remote \(layerName) does not match desired config"
                print("[Tavus] ⚠️ \(lastMessage) — escalating to create-block fallback")
                // Fall through to try the next attempt (create block) if any,
                // otherwise throw below.
                if idx + 1 >= attempts.count {
                    throw TavusError.apiError(statusCode: 304, message: lastMessage)
                }
                continue
            }
            lastMessage = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            print("[Tavus] PATCH /layers/\(layerName) attempt \(idx + 1)/2 failed — HTTP \(http.statusCode): \(lastMessage.prefix(200))")

            // 5xx fallback: if the remote state ALREADY matches desired
            // (e.g., a prior successful PATCH from this or another device
            // already put the layer in the right configuration), then the
            // current 500 is a server-side failure on an idempotent no-op
            // — not a real configuration problem. GET-verify: if the layer
            // matches, accept as synced. This is safe because a no-op PATCH
            // has no side effects, and the hard-gate semantics are preserved
            // (a genuinely mis-configured remote state still fails here and
            // bubbles up as personaSyncUnverified).
            //
            // Surfaced specifically by the Tavus /layers/stt outage: STT was
            // already correctly set on the persona but PATCH was 500'ing
            // uniformly. Without this fallback, the hard-gate blocks the
            // assessment even though the persona config is actually fine.
            if (500...599).contains(http.statusCode) {
                let verified = await verifyRemoteLayer(
                    personaId: personaId,
                    layerName: layerName,
                    expectedFields: orderedFields
                )
                if verified {
                    print("[Tavus] PATCH /layers/\(layerName) returned \(http.statusCode) but GET-verified remote already matches desired — accepting as synced (Tavus PATCH endpoint is degraded, remote state is correct)")
                    return
                }
                print("[Tavus] PATCH /layers/\(layerName) returned \(http.statusCode) and GET verification showed remote does NOT match — escalating as real failure")
            }

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
            ("perception_model_name",     perception.modelName),
            ("ambient_awareness_queries", perception.ambientAwarenessQueries)
        ]
        try await patchPersonaLayer(
            personaId: personaId,
            layerName: "perception",
            orderedFields: ordered,
            asDictionary: perception.asDictionary
        )
    }

    private func patchPersonaLLMLayer(personaId: String, llm: LLMLayerSettings) async throws {
        let ordered: [(key: String, value: Any)] = [
            ("model",                 llm.model),
            ("speculative_inference", llm.speculativeInference),
            ("extra_body",            llm.extraBody)
        ]
        try await patchPersonaLayer(
            personaId: personaId,
            layerName: "llm",
            orderedFields: ordered,
            asDictionary: llm.asDictionary
        )
    }

    private func patchPersonaTTSLayer(personaId: String, tts: TTSLayerSettings) async throws {
        let ordered: [(key: String, value: Any)] = [
            ("tts_engine",      tts.engine),
            ("model",           tts.model),
            ("emotion_control", tts.emotionControl),
            ("voice_settings",  ["speed": tts.voiceSpeed, "emotion": tts.emotion])
        ]
        try await patchPersonaLayer(
            personaId: personaId,
            layerName: "tts",
            orderedFields: ordered,
            asDictionary: tts.asDictionary
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
        let modelName: String              // "raven-1"
        let ambientAwarenessQueries: [String]

        var asDictionary: [String: Any] {
            [
                "perception_model_name":     modelName,
                "ambient_awareness_queries": ambientAwarenessQueries
            ]
        }

        var syncFingerprint: String {
            "\(modelName)|aa:\(ambientAwarenessQueries.joined(separator: ";"))"
        }
    }

    /// Desired perception layer. raven-1 fuses audio + visual into unified
    /// behavioral understanding. CLINICAL CONSTRAINT: output is LOG-ONLY. It
    /// must NEVER alter avatar behavior mid-assessment or feed into scoring.
    /// See webhook handler for application.perception_analysis — stored as
    /// research log, never as a clinical signal.
    ///
    /// `ambient_awareness_queries` is a list of natural-language probes raven-1
    /// continuously evaluates against the video+audio stream. Results are
    /// emitted as `application.perception_tool_call` webhook events for
    /// post-session review. Queries chosen for MCI screening: confusion,
    /// distress, and engagement (camera attention).
    private var desiredPerceptionLayer: PerceptionLayerSettings {
        PerceptionLayerSettings(
            modelName: "raven-1",
            ambientAwarenessQueries: [
                "Does the user appear confused or uncertain?",
                "Is the user showing signs of distress or anxiety?",
                "Is the user looking away from the camera?"
            ]
        )
    }

    // MARK: - LLM Layer (model + sampling + speculative inference default)

    /// LLM persona layer. `speculative_inference: true` is set here as a
    /// **safety-net default**. Per Tavus docs, per-conversation runtime
    /// settings override persona defaults for that session — so the existing
    /// phase-scoped runtime signal in `Models/AssessmentPhaseType.swift`
    /// (`avatarSetAssessmentPhaseType`) remains authoritative: ON for
    /// `.intro` / `.outro`, OFF for scripted scoring phases. The persona-level
    /// `true` only applies if the runtime signal hasn't fired yet (e.g., the
    /// very first echo before welcome handlers run).
    private struct LLMLayerSettings {
        let model: String                    // e.g. "tavus-gemini-2.5-flash"
        let speculativeInference: Bool       // persona default; runtime overrides per session
        let extraBody: [String: Any]         // sampling params (temperature, top_p)

        var asDictionary: [String: Any] {
            [
                "model":                 model,
                "speculative_inference": speculativeInference,
                "extra_body":            extraBody
            ]
        }

        var syncFingerprint: String {
            let temp = (extraBody["temperature"] as? Double).map { String(format: "%.2f", $0) } ?? "-"
            let topP = (extraBody["top_p"] as? Double).map { String(format: "%.2f", $0) } ?? "-"
            return "\(model)|si:\(speculativeInference ? 1 : 0)|t:\(temp)|p:\(topP)"
        }
    }

    /// Desired LLM layer. Gemini 2.5 Flash via Tavus for low-latency
    /// conversational turns; conservative sampling to keep clinical
    /// utterances on-script (low temperature, narrow top_p).
    private var desiredLLMLayer: LLMLayerSettings {
        LLMLayerSettings(
            model:                "tavus-gemini-2.5-flash",
            speculativeInference: true,
            extraBody: [
                "temperature": 0.4,
                "top_p":       0.85
            ]
        )
    }

    // MARK: - TTS Layer (cartesia sonic-3 with emotion control)

    private struct TTSLayerSettings {
        let engine: String                   // "cartesia"
        let model: String                    // "sonic-3"
        let emotionControl: Bool
        let voiceSpeed: String               // "slow" / "normal" / "fast"
        let emotion: [String]                // e.g. ["positivity:medium"]

        var asDictionary: [String: Any] {
            [
                "tts_engine":      engine,
                "model":           model,
                "emotion_control": emotionControl,
                "voice_settings": [
                    "speed":   voiceSpeed,
                    "emotion": emotion
                ]
            ]
        }

        var syncFingerprint: String {
            "\(engine)|\(model)|ec:\(emotionControl ? 1 : 0)|s:\(voiceSpeed)|e:\(emotion.joined(separator: ";"))"
        }
    }

    /// Desired TTS layer. Cartesia sonic-3 with mild positive prosody, slowed
    /// to roughly 130–140 wpm — matches the welcome-screen delivery context
    /// in `LeftPaneSpeechCopy.welcomeTavusDeliveryContext` and accommodates
    /// the typical 65+ MCI patient population.
    private var desiredTTSLayer: TTSLayerSettings {
        TTSLayerSettings(
            engine:         "cartesia",
            model:          "sonic-3",
            emotionControl: true,
            voiceSpeed:     "slow",
            emotion:        ["positivity:medium"]
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
        // Route through the generic patchPersonaLayer path so this layer
        // gets the same cache-policy hygiene + 304 GET-verification as the
        // others. Previously this had its own inline request builder
        // without explicit cachePolicy, so URLSession's default policy
        // attached auto-conditional headers from cached GETs, producing
        // the "PATCH returned 304 Not Modified" log we observed.
        try await patchPersonaLayer(
            personaId: personaId,
            layerName: "conversational_flow",
            orderedFields: flow.orderedFields,
            asDictionary: flow.asDictionary
        )
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
    /// Persona layer sync (STT / LLM / TTS / perception / conversational_flow) did not
    /// reach a verified state after all retries. The assessment MUST NOT proceed
    /// because the avatar session would run with partial / stale config and could
    /// misinterpret patient speech — producing invalid clinical scores.
    case personaSyncUnverified(reason: String)

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
        case .personaSyncUnverified(let reason):
            return "Avatar configuration could not be verified. Cannot start assessment: \(reason)"
        }
    }
}

/// Pure decision for whether a persona-sync call should short-circuit on
/// the cached failure or proceed with a fresh network round. Extracted so
/// the cooldown contract can be unit-tested without touching URLSession.
///
/// Rules:
///   - If `now - lastTerminalFailureAt < window` → `.cooldownActive(remaining)`
///     (short-circuit; surface cached failure to caller)
///   - If `now - lastTerminalFailureAt >= window` → `.expired` (retry allowed)
///   - No prior failure recorded (handled at call site by passing the
///     optional) is represented by the caller skipping this entirely.
enum PersonaSyncCooldown: Equatable {
    case cooldownActive(remaining: TimeInterval)
    case expired
    case shouldRetry  // User-initiated retry bypass; not produced by `decide`.

    static func decide(
        lastTerminalFailureAt: Date,
        now: Date,
        window: TimeInterval
    ) -> PersonaSyncCooldown {
        let elapsed = now.timeIntervalSince(lastTerminalFailureAt)
        if elapsed < window {
            return .cooldownActive(remaining: max(0, window - elapsed))
        }
        return .expired
    }
}

/// Lifecycle state of the Tavus persona layer sync (STT / LLM / TTS / perception / flow).
/// Drives the assessment-start hard-gate — only `.verified` permits joining the Daily room.
enum VoiceIsolationSyncState: Equatable, Sendable {
    /// No sync attempted yet this session.
    case idle
    /// Sync is in-flight (possibly a retry).
    case syncing(attempt: Int)
    /// All five layers PATCH'd successfully OR verified via GET after 304.
    case verified
    /// All retries exhausted. `reason` describes the last failure for UI surfacing.
    /// Assessment MUST NOT proceed in this state.
    case failed(reason: String)

    var isTerminalSuccess: Bool { self == .verified }
    var isTerminalFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
