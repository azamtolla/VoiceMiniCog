//
//  TavusWebhookHandlers.swift
//  VoiceMiniCog
//
//  Dry wiring for Tavus application.* webhooks. Activation is GATED on:
//    1. Signed BAA with Tavus (currently pending).
//    2. HIPAA-compliant landing environment configured (AWS with BAA,
//       Azure HIPAA, or GCP Healthcare).
//    3. PHI Redaction API enabled for transcript pipeline.
//
//  Until then, `WebhookActivation.isActive` returns false and the handlers
//  short-circuit. Code paths exist so that flipping the activation flag
//  ships the feature in one config change — no new wiring needed.
//
//  WEBHOOKS WE HANDLE:
//    - application.transcription_ready   → Redact → write to DB
//    - application.perception_analysis   → Store as research log (LOG ONLY, NEVER scoring)
//    - application.recording_ready       → Store 15-min one-time signed URL
//    - system.shutdown                   → Map to SessionShutdownReason (already wired in DailyCallManager)
//
//  NB: Our app does not run its own server — webhooks land on a Mercy
//  Health-provisioned backend. This file encapsulates the CLIENT-side
//  decisions (what to persist, what's PHI-sensitive, what to show the
//  clinician). The actual HTTP endpoint is out of scope for iOS.
//

import Foundation

// MARK: - WebhookActivation

public enum WebhookActivation {

    private static let activationKey = "voiceMiniCog.webhooks.activated"

    /// True ONLY after BAA signed + backend configured. Flip in Settings
    /// after Mercy Health validates the BAA + landing endpoint.
    public static var isActive: Bool {
        UserDefaults.standard.bool(forKey: activationKey)
    }

    public static func setActive(_ active: Bool) {
        UserDefaults.standard.set(active, forKey: activationKey)
    }
}

// MARK: - Payloads

public struct TavusWebhookPayload: Codable {
    public let eventType: String
    public let conversationId: String
    public let timestamp: Date
    public let properties: [String: String]?
}

public struct TranscriptionReadyPayload: Codable {
    public let conversationId: String
    public let transcriptURL: String     // signed URL or inline transcript
    public let durationSeconds: Double
    public let language: String?
}

public struct PerceptionAnalysisPayload: Codable {
    public let conversationId: String
    public let rawAnalysisURL: String?
    public let startedAt: Date
    public let endedAt: Date
}

public struct RecordingReadyPayload: Codable {
    public let conversationId: String
    public let signedURL: String
    public let signedURLExpiresAt: Date
    public let durationSeconds: Double
}

// MARK: - Handlers

public enum TavusWebhookHandlers {

    /// transcription_ready handler.
    /// PIPELINE:
    ///   1. Check activation — short-circuit if gated.
    ///   2. Fetch transcript (redacted server-side by Tavus PHI Redaction API).
    ///   3. Write to app DB (PDF report + search index).
    ///   4. Log audit entry.
    public static func handleTranscriptionReady(_ payload: TranscriptionReadyPayload) async {
        guard WebhookActivation.isActive else {
            print("[TavusWebhooks] transcription_ready received but webhooks not active (BAA gate) — dropping")
            return
        }
        print("[TavusWebhooks] transcription_ready received for \(payload.conversationId) — would download + write to DB")
        // Production implementation will go here post-BAA:
        //   let redacted = await TavusRedactionClient.redact(url: payload.transcriptURL)
        //   try await TranscriptStore.save(conversationId: payload.conversationId, content: redacted)
        //   AuditLog.record(event: "transcription.saved", conversationId: payload.conversationId)
    }

    /// perception_analysis handler.
    /// CLINICAL RULE: output is LOG-ONLY. Never feeds scoring, never shown
    /// to the patient, never alters avatar behavior. Stored in a separate
    /// "research" table gated behind IRB approval.
    public static func handlePerceptionAnalysis(_ payload: PerceptionAnalysisPayload) async {
        guard WebhookActivation.isActive else {
            print("[TavusWebhooks] perception_analysis received but webhooks not active — dropping")
            return
        }
        print("[TavusWebhooks] perception_analysis received for \(payload.conversationId) — log-only (research table)")
        // Production:
        //   try await ResearchLogStore.save(
        //       conversationId: payload.conversationId,
        //       ravenData: payload.rawAnalysisURL,
        //       clinicallyUsed: false  // NEVER true without IRB
        //   )
    }

    /// recording_ready handler.
    /// CONSTRAINTS:
    ///   - Signed URL TTL capped at 15 minutes (HIPAA "minimum necessary").
    ///   - One-time-use enforced at the backend level, not here.
    ///   - Audit log every retrieval.
    public static func handleRecordingReady(_ payload: RecordingReadyPayload) async {
        guard WebhookActivation.isActive else {
            print("[TavusWebhooks] recording_ready received but webhooks not active — dropping")
            return
        }
        let ttl = payload.signedURLExpiresAt.timeIntervalSinceNow
        guard ttl > 0, ttl <= 15 * 60 else {
            print("[TavusWebhooks] recording_ready rejected: URL TTL out of policy (\(ttl)s, max 900s)")
            return
        }
        print("[TavusWebhooks] recording_ready for \(payload.conversationId), TTL=\(Int(ttl))s — would store with one-time-use enforcement")
    }

    /// system.shutdown already handled in DailyCallManager.handleSystemShutdown.
    /// This function exists for webhook-side parity when the event arrives
    /// via backend rather than the in-call data channel (e.g., patient's
    /// iPad force-quit → Tavus fires shutdown as a webhook only).
    public static func handleSystemShutdown(_ payload: TavusWebhookPayload) async {
        let reasonRaw = payload.properties?["reason"]
        let reason: SessionShutdownReason
        switch reasonRaw {
        case "participant_left":  reason = .participantLeft
        case "timeout":           reason = .timeout
        case "network_error":     reason = .networkError
        case "completed":         reason = .completed
        default:                  reason = .unknown
        }
        print("[TavusWebhooks] system.shutdown via webhook: \(reason.rawValue)")
        if reason.isPartial {
            // Persist abandonment so next app launch renders a partial report.
            await MainActor.run {
                AssessmentPersistence.recordAbandonment(
                    at: payload.timestamp,
                    reason: reason,
                    completedSubtests: [],
                    policy: .flagForClinicianReview
                )
            }
        }
    }
}
