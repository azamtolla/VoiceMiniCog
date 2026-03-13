//
//  RealtimeManager.swift
//  VoiceMiniCog
//
//  Manages OpenAI Realtime connection via WebRTC
//  Provides low-latency bidirectional voice conversation
//
//  IMPORTANT: This file requires WebRTC dependency.
//  Add to Xcode: File > Add Package Dependencies...
//  URL: https://github.com/nickvido/webrtc-swiftpm
//  Or: https://github.com/nickovideo/WebRTC (official builds)
//

import Foundation
import AVFoundation

// TODO: Uncomment when WebRTC package is added
// import WebRTC

// MARK: - Connection State

enum RealtimeConnectionState: String {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed
}

// MARK: - Realtime Events

enum RealtimeEvent {
    case connected
    case disconnected(Error?)
    case transcriptUpdate(role: String, text: String, isFinal: Bool)
    case assistantSpeechStarted
    case assistantSpeechEnded
    case userSpeechStarted
    case userSpeechEnded
    case error(Error)
    case phaseInstruction(phase: String)
}

// MARK: - Realtime Manager Delegate

protocol RealtimeManagerDelegate: AnyObject {
    func realtimeManager(_ manager: RealtimeManager, didReceiveEvent event: RealtimeEvent)
    func realtimeManager(_ manager: RealtimeManager, connectionStateChanged state: RealtimeConnectionState)
}

// MARK: - Realtime Manager

@Observable
final class RealtimeManager {

    // MARK: - Published State

    var connectionState: RealtimeConnectionState = .disconnected
    var isAssistantSpeaking: Bool = false
    var isUserSpeaking: Bool = false
    var currentTranscript: String = ""
    var errorMessage: String?

    // MARK: - Delegate

    weak var delegate: RealtimeManagerDelegate?

    // MARK: - Private Properties

    private var clientSecret: String?
    private let audioSessionManager = AudioSessionManager.shared
    private let tokenService = TokenService.shared

    // TODO: Uncomment when WebRTC is added
    // private var peerConnection: RTCPeerConnection?
    // private var dataChannel: RTCDataChannel?
    // private var localAudioTrack: RTCAudioTrack?
    // private var peerConnectionFactory: RTCPeerConnectionFactory?

    // MARK: - Configuration

    /// OpenAI Realtime model to use
    let model = "gpt-4o-realtime-preview-2024-12-17"

    /// Voice for the assistant
    let voice = "sage" // Options: alloy, ash, ballad, coral, echo, sage, shimmer, verse

    // MARK: - Initialization

    init() {
        // TODO: Initialize WebRTC factory when package is added
        // setupWebRTCFactory()
    }

    // MARK: - Public Methods

    /// Start a realtime session
    /// Fetches token, configures audio, and establishes WebRTC connection
    func startSession() async {
        guard connectionState == .disconnected || connectionState == .failed else {
            print("[Realtime] Session already active or connecting")
            return
        }

        connectionState = .connecting
        errorMessage = nil

        // Check microphone permission
        guard await audioSessionManager.checkMicrophonePermission() else {
            handleError(RealtimeError.microphonePermissionDenied)
            return
        }

        // Configure audio session
        do {
            try audioSessionManager.configureForRealtimeVoice()
        } catch {
            handleError(RealtimeError.audioSessionFailed(error))
            return
        }

        // Fetch ephemeral token from backend
        do {
            clientSecret = try await tokenService.fetchRealtimeToken()
        } catch {
            handleError(RealtimeError.tokenFetchFailed(error))
            return
        }

        // Establish WebRTC connection
        await establishConnection()
    }

    /// Stop the realtime session
    func stopSession() {
        print("[Realtime] Stopping session")

        // TODO: Close WebRTC connection when package is added
        // dataChannel?.close()
        // peerConnection?.close()
        // peerConnection = nil
        // dataChannel = nil

        connectionState = .disconnected
        isAssistantSpeaking = false
        isUserSpeaking = false
        clientSecret = nil

        delegate?.realtimeManager(self, didReceiveEvent: .disconnected(nil))
        delegate?.realtimeManager(self, connectionStateChanged: .disconnected)
    }

    /// Send instruction text to the assistant
    /// Use this to guide the conversation flow
    func sendInstructionText(_ instruction: String) {
        guard connectionState == .connected else {
            print("[Realtime] Cannot send instruction - not connected")
            return
        }

        let message: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": instruction
                    ]
                ]
            ]
        ]

        sendDataChannelMessage(message)

        // Trigger response generation
        let responseMessage: [String: Any] = [
            "type": "response.create"
        ]
        sendDataChannelMessage(responseMessage)
    }

    /// Interrupt the assistant's current speech
    func interruptAssistant() {
        guard connectionState == .connected else { return }

        let message: [String: Any] = [
            "type": "response.cancel"
        ]
        sendDataChannelMessage(message)

        isAssistantSpeaking = false
    }

    /// Update session configuration (e.g., system instructions)
    func updateSessionConfig(instructions: String) {
        guard connectionState == .connected else { return }

        let message: [String: Any] = [
            "type": "session.update",
            "session": [
                "instructions": instructions,
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.5,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 500
                ]
            ]
        ]
        sendDataChannelMessage(message)
    }

    // MARK: - Private Methods

    private func establishConnection() async {
        // TODO: Implement WebRTC connection when package is added
        // This is where you would:
        // 1. Create RTCPeerConnection with STUN/TURN servers
        // 2. Create local audio track from microphone
        // 3. Create data channel for signaling
        // 4. Create SDP offer
        // 5. Send offer to OpenAI's /v1/realtime endpoint with client_secret
        // 6. Set remote SDP answer
        // 7. Handle ICE candidates

        print("[Realtime] WebRTC connection not implemented - add WebRTC package first")
        print("[Realtime] See OPENAI_REALTIME_BACKEND_NOTES.md for setup instructions")

        // Simulate connection for testing UI flow
        #if DEBUG
        await simulateConnectionForTesting()
        #else
        handleError(RealtimeError.webRTCNotInstalled)
        #endif
    }

    #if DEBUG
    private func simulateConnectionForTesting() async {
        // Simulate connection delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        connectionState = .connected
        delegate?.realtimeManager(self, connectionStateChanged: .connected)
        delegate?.realtimeManager(self, didReceiveEvent: .connected)

        print("[Realtime] DEBUG: Simulated connection established")
    }
    #endif

    private func sendDataChannelMessage(_ message: [String: Any]) {
        // TODO: Send via RTCDataChannel when WebRTC is added
        guard let data = try? JSONSerialization.data(withJSONObject: message) else {
            print("[Realtime] Failed to serialize message")
            return
        }

        print("[Realtime] Would send: \(String(data: data, encoding: .utf8) ?? "")")

        // TODO: Uncomment when WebRTC is added
        // let buffer = RTCDataBuffer(data: data, isBinary: false)
        // dataChannel?.sendData(buffer)
    }

    private func handleError(_ error: RealtimeError) {
        connectionState = .failed
        errorMessage = error.localizedDescription
        delegate?.realtimeManager(self, didReceiveEvent: .error(error))
        delegate?.realtimeManager(self, connectionStateChanged: .failed)
        print("[Realtime] Error: \(error.localizedDescription)")
    }

    // MARK: - WebRTC Event Handlers (TODO: Implement when package added)

    /*
    private func setupWebRTCFactory() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: decoderFactory
        )
    }

    private func handleDataChannelMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created":
            print("[Realtime] Session created")

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                currentTranscript = transcript
                delegate?.realtimeManager(self, didReceiveEvent: .transcriptUpdate(role: "user", text: transcript, isFinal: true))
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                currentTranscript += delta
                delegate?.realtimeManager(self, didReceiveEvent: .transcriptUpdate(role: "assistant", text: currentTranscript, isFinal: false))
            }

        case "response.audio_transcript.done":
            if let transcript = json["transcript"] as? String {
                delegate?.realtimeManager(self, didReceiveEvent: .transcriptUpdate(role: "assistant", text: transcript, isFinal: true))
            }

        case "input_audio_buffer.speech_started":
            isUserSpeaking = true
            delegate?.realtimeManager(self, didReceiveEvent: .userSpeechStarted)

        case "input_audio_buffer.speech_stopped":
            isUserSpeaking = false
            delegate?.realtimeManager(self, didReceiveEvent: .userSpeechEnded)

        case "response.audio.started":
            isAssistantSpeaking = true
            delegate?.realtimeManager(self, didReceiveEvent: .assistantSpeechStarted)

        case "response.audio.done":
            isAssistantSpeaking = false
            delegate?.realtimeManager(self, didReceiveEvent: .assistantSpeechEnded)

        case "error":
            if let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                handleError(RealtimeError.serverError(message))
            }

        default:
            print("[Realtime] Unhandled event: \(type)")
        }
    }
    */
}

// MARK: - Realtime Errors

enum RealtimeError: Error, LocalizedError {
    case microphonePermissionDenied
    case audioSessionFailed(Error)
    case tokenFetchFailed(Error)
    case connectionFailed(Error)
    case webRTCNotInstalled
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required for voice conversation"
        case .audioSessionFailed(let error):
            return "Audio setup failed: \(error.localizedDescription)"
        case .tokenFetchFailed(let error):
            return "Failed to get realtime token: \(error.localizedDescription)"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .webRTCNotInstalled:
            return "WebRTC package not installed. Add the WebRTC Swift package to your project."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - WebRTC Delegate Extensions (TODO: Implement when package added)

/*
extension RealtimeManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("[Realtime] Signaling state: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[Realtime] Stream added")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("[Realtime] Stream removed")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("[Realtime] Should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("[Realtime] ICE connection state: \(newState.rawValue)")
        DispatchQueue.main.async {
            switch newState {
            case .connected, .completed:
                self.connectionState = .connected
                self.delegate?.realtimeManager(self, connectionStateChanged: .connected)
            case .disconnected:
                self.connectionState = .reconnecting
                self.delegate?.realtimeManager(self, connectionStateChanged: .reconnecting)
            case .failed:
                self.connectionState = .failed
                self.delegate?.realtimeManager(self, connectionStateChanged: .failed)
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("[Realtime] ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // ICE candidates are typically trickled - for OpenAI Realtime we gather all first
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[Realtime] Data channel opened")
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }
}

extension RealtimeManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("[Realtime] Data channel state: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        handleDataChannelMessage(buffer.data)
    }
}
*/
