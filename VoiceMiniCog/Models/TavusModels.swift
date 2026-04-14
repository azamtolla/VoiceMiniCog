//
//  TavusModels.swift
//  VoiceMiniCog
//

import Foundation

/// Tavus persona `layers.conversational_flow.voice_isolation` (participant mic processing).
/// See https://docs.tavus.io/sections/conversational-video-interface/persona/conversational-flow
enum TavusVoiceIsolation: String, CaseIterable, Identifiable {
    case off
    case near

    var id: String { rawValue }

    var settingsLabel: String {
        switch self {
        case .off: "Off (raw mic)"
        case .near: "Near (~1 m)"
        }
    }
}

struct TavusConversationCreateRequest: Codable {
    let replica_id: String
    let persona_id: String
}

struct TavusConversationSession: Codable {
    let conversation_id: String
    let conversation_name: String?
    let conversation_url: String
    let status: String?
    let meeting_token: String?
}

struct TavusInteraction<Properties: Codable>: Codable {
    let message_type: String
    let event_type: String
    let conversation_id: String
    let properties: Properties?
}

struct EmptyProperties: Codable {}

struct EchoProperties: Codable {
    let modality: String
    let text: String?
    let audio: String?
    let sample_rate: Int
    let inference_id: String
    let done: Bool
}

struct SensitivityProperties: Codable {
    let participant_pause_sensitivity: String
    let participant_interrupt_sensitivity: String
}

struct RespondProperties: Codable {
    let text: String
}

struct OverwriteContextProperties: Codable {
    let context: String
}

struct ReplicaSpeakingProperties: Codable {
    let inference_id: String?
    let duration: Double?
    let interrupted: Bool?
}

struct TavusEventEnvelope: Codable {
    let message_type: String
    let event_type: String
    let conversation_id: String?
    let seq: Int?
    let turn_idx: Int?
    let properties: ReplicaSpeakingProperties?
}
