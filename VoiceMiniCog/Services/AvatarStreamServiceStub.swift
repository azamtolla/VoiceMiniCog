//
//  AvatarStreamServiceStub.swift
//  VoiceMiniCog
//
//  Stub for AvatarStreamService so MiniCogLiveView compiles.
//  Will be replaced by PersonaBridge + Daily SDK integration.
//

import Foundation
import SwiftUI

enum TavusAssistantState: String {
    case idle, speaking, listening, thinking
}

@Observable
class AvatarStreamService {
    var blendshapes: [String: Float] = [:]
    var assistantState: TavusAssistantState = .idle
    var transcriptPreview: String = ""
    var isConnected: Bool = false
    var isVoiceOnlyFallback: Bool = false
    var errorBannerMessage: String? = nil

    struct Metrics {
        var reconnectCount: Int = 0
        var droppedFrameCount: Int = 0
        var lastRoundTripMs: Double? = nil
    }
    var metrics = Metrics()

    func connect() {
        // Stub — will be replaced by PersonaBridge.createAndJoinConversation()
        errorBannerMessage = "Avatar not connected. PersonaBridge integration pending."
    }

    func disconnect() {
        isConnected = false
    }

    func startMicStreaming() {}
    func stopMicStreaming() {}
}
