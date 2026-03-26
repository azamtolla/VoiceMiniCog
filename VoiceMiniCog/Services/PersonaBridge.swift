//
//  PersonaBridge.swift
//  VoiceMiniCog
//
//  Manages Tavus conversation lifecycle + Daily call.
//  Daily iOS SDK: https://github.com/daily-co/daily-ios (add via SPM)
//

import Foundation
#if canImport(Daily)
import Daily
#endif

@Observable
final class PersonaBridge: NSObject {

    var conversationId: String?
    var conversationURL: String?
    var meetingToken: String?
    var isConnected = false
    var replicaIsSpeaking = false
    var userIsSpeaking = false
    var lastError: String?

    weak var replicaEventObserver: ReplicaEventObserving?

    private let apiClient: APIClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    #if canImport(Daily)
    private let callClient = CallClient()
    #endif

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
        super.init()
        #if canImport(Daily)
        callClient.delegate = self
        #endif
    }

    // MARK: - Lifecycle

    func createAndJoinConversation(replicaId: String, personaId: String) async {
        do {
            let session = try await apiClient.createTavusConversation(replicaId: replicaId, personaId: personaId)
            conversationId = session.conversation_id
            conversationURL = session.conversation_url
            meetingToken = session.meeting_token
            #if canImport(Daily)
            callClient.join(url: session.conversation_url, token: session.meeting_token)
            isConnected = true
            #else
            lastError = "Daily SDK not installed"
            #endif
        } catch {
            lastError = "Tavus conversation failed: \(error.localizedDescription)"
        }
    }

    func leaveConversation() {
        #if canImport(Daily)
        callClient.leave()
        #endif
        isConnected = false
    }

    // MARK: - Hold / Release (used by AudioArbitrator + ScriptClipPlayer)

    func holdPersonaPlex() async {
        guard let cid = conversationId else { return }
        await sendInterrupt(conversationId: cid)
        await sendSensitivity(conversationId: cid, pause: "low", interrupt: "low")
    }

    func releasePersonaPlex() async {
        guard let cid = conversationId else { return }
        await sendSensitivity(conversationId: cid, pause: "medium", interrupt: "medium")
    }

    // MARK: - Interaction Senders

    func sendEchoInteraction(clipData: Data, clipId: String, transcript: String?) async {
        guard let cid = conversationId else { return }
        let props = EchoProperties(
            modality: "audio", text: transcript,
            audio: clipData.base64EncodedString(),
            sample_rate: 24000, inference_id: clipId, done: true
        )
        let interaction = TavusInteraction(
            message_type: "conversation", event_type: "conversation.echo",
            conversation_id: cid, properties: props
        )
        await sendInteraction(interaction)
    }

    func sendRespondInteraction(text: String) async {
        guard let cid = conversationId else { return }
        let interaction = TavusInteraction(
            message_type: "conversation", event_type: "conversation.respond",
            conversation_id: cid, properties: RespondProperties(text: text)
        )
        await sendInteraction(interaction)
    }

    func overwriteContext(_ context: String) async {
        guard let cid = conversationId else { return }
        let interaction = TavusInteraction(
            message_type: "conversation", event_type: "conversation.overwrite_context",
            conversation_id: cid, properties: OverwriteContextProperties(context: context)
        )
        await sendInteraction(interaction)
    }

    // MARK: - Private Helpers

    private func sendInterrupt(conversationId: String) async {
        let interaction = TavusInteraction<EmptyProperties>(
            message_type: "conversation", event_type: "conversation.interrupt",
            conversation_id: conversationId, properties: nil
        )
        await sendInteraction(interaction)
    }

    private func sendSensitivity(conversationId: String, pause: String, interrupt: String) async {
        let interaction = TavusInteraction(
            message_type: "conversation", event_type: "conversation.sensitivity",
            conversation_id: conversationId,
            properties: SensitivityProperties(
                participant_pause_sensitivity: pause,
                participant_interrupt_sensitivity: interrupt
            )
        )
        await sendInteraction(interaction)
    }

    private func sendInteraction<P: Codable>(_ interaction: TavusInteraction<P>) async {
        #if canImport(Daily)
        do {
            let data = try encoder.encode(interaction)
            callClient.sendAppMessage(json: data, to: .all)
        } catch {
            await MainActor.run { self.lastError = "Send failed: \(error.localizedDescription)" }
        }
        #else
        await MainActor.run { self.lastError = "Daily SDK not installed" }
        #endif
    }
}

// MARK: - Daily Delegate

#if canImport(Daily)
extension PersonaBridge: CallClientDelegate {
    func callClient(_ callClient: CallClient, receivedAppMessage data: Data, from participant: Participant) {
        guard let envelope = try? decoder.decode(TavusEventEnvelope.self, from: data) else { return }

        switch envelope.event_type {
        case "conversation.replica.started_speaking":
            replicaIsSpeaking = true
            replicaEventObserver?.onReplicaStartedSpeaking(inferenceId: envelope.properties?.inference_id)
        case "conversation.replica.stopped_speaking":
            replicaIsSpeaking = false
            replicaEventObserver?.onReplicaStoppedSpeaking(
                inferenceId: envelope.properties?.inference_id,
                duration: envelope.properties?.duration,
                interrupted: envelope.properties?.interrupted ?? false
            )
        case "conversation.user.started_speaking":
            userIsSpeaking = true
            replicaEventObserver?.onUserStartedSpeaking()
        case "conversation.user.stopped_speaking":
            userIsSpeaking = false
            replicaEventObserver?.onUserStoppedSpeaking()
        default:
            break
        }
    }
}
#endif
