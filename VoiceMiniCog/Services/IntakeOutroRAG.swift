//
//  IntakeOutroRAG.swift
//  VoiceMiniCog
//
//  Per-conversation Tavus Knowledge Base (RAG) wiring — WRAPPER PHASES ONLY.
//
//  CLINICAL CONSTRAINT:
//  RAG is HARD-LOCKED OUT of scored subtest phases. The avatar's job during
//  orientation / registration / clock / recall / fluency / story-recall is
//  to deliver scripted conversation.echo utterances verbatim. Any RAG
//  retrieval during those phases risks:
//    - Leaking clinic-specific content into scored speech (validity).
//    - Generating unscripted utterances (protocol adherence).
//    - Inflating latency.
//
//  USE CASES (intro + outro only):
//    - Intake: patient name confirmation, hearing check, language preference
//    - Outro: clinic-specific "what happens next" grounded in Mercy Health
//      protocol (booking a follow-up, triage path, who calls you when)
//
//  Implementation:
//    - `document_ids` is supplied at /v2/conversations create time
//      (TavusService.createConversation).
//    - During scored subtests, phase views call `avatarSetAssessmentPhaseType`
//      which pushes `rag_enabled: false` via overwrite_llm_context.
//

import Foundation

public struct IntakeOutroRAG {

    /// Document IDs registered in Tavus Knowledge Base, keyed by purpose.
    /// Set by MA or clinic admin in Settings. NOT hardcoded — each clinic
    /// uploads its own protocol docs.
    public struct DocumentIDs: Codable, Equatable {
        public var intakeDocID: String?       // Patient intake FAQ
        public var outroDocID: String?        // "What happens next" protocol
        public var clinicProtocolDocID: String?   // General clinic policy

        public init(intakeDocID: String? = nil,
                    outroDocID: String? = nil,
                    clinicProtocolDocID: String? = nil) {
            self.intakeDocID = intakeDocID
            self.outroDocID = outroDocID
            self.clinicProtocolDocID = clinicProtocolDocID
        }

        /// Which docs to pass to a Tavus conversation given the current phase.
        /// Returns `[]` for any scored subtest phase (RAG hard-locked out).
        public func documentIDs(for phase: AssessmentPhaseType) -> [String] {
            switch phase {
            case .intro:
                return [intakeDocID, clinicProtocolDocID].compactMap { $0 }
            case .outro:
                return [outroDocID, clinicProtocolDocID].compactMap { $0 }
            case .orientation, .wordRegistration, .verbalFluency,
                 .clockDrawing, .storyRecall, .wordRecall:
                // HARD LOCK: no RAG during scored subtests.
                return []
            }
        }
    }

    // MARK: - Persistence

    private static let storageKey = "voiceMiniCog.intakeOutroRAG.documentIDs"

    public static func currentDocumentIDs() -> DocumentIDs {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return DocumentIDs()
        }
        return (try? JSONDecoder().decode(DocumentIDs.self, from: data)) ?? DocumentIDs()
    }

    public static func save(_ ids: DocumentIDs) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - LLM-context payload

    /// Build the `conversation.overwrite_llm_context` payload for a phase
    /// transition. Includes:
    ///   - speculative_inference on/off (from AssessmentPhaseType)
    ///   - rag_enabled on/off (hard-locked to false for scored subtests)
    ///   - document_ids for the current phase (empty for scored subtests)
    public static func llmContextPayload(for phase: AssessmentPhaseType) -> [String: Any] {
        let docs = currentDocumentIDs().documentIDs(for: phase)
        return [
            "llm": [
                "speculative_inference": phase.allowsSpeculativeInference,
                "rag_enabled": !phase.isScoredSubtest
            ],
            "rag": [
                "document_ids": docs,
                "enabled": !phase.isScoredSubtest
            ]
        ]
    }
}
