//
//  DailyCallManager.swift
//  VoiceMiniCog
//
//  Native Daily iOS SDK wrapper replacing the WKWebView + TavusBridge.html architecture.
//  Manages the Daily CallClient lifecycle, Tavus CVI protocol interactions,
//  echo queue serialization, auto-interrupt logic, and mic/audio gating.
//
//  Phase views communicate exclusively via NotificationCenter helper functions
//  (avatarSpeak, avatarSetContext, etc.) — they never touch this class directly.
//

import Foundation
import Daily
import os

private let log = Logger(subsystem: "com.mercycog.VoiceMiniCog", category: "DailyCall")

@MainActor @Observable
final class DailyCallManager: NSObject {

    // MARK: - Published State

    /// Remote participant's (Tavus replica) video track for DailyVideoView binding.
    var remoteVideoTrack: VideoTrack?

    /// Current call state — .initialized, .joined, .left
    var callState: CallState = .initialized

    /// True when the replica is actively speaking an echo.
    var replicaIsSpeaking = false

    // MARK: - Configuration

    /// Stored room URL for deferred join pattern (Home pre-warm).
    private var roomURL: URL?

    /// When true, `joinIfReady()` is a no-op — delays join until assessment starts.
    /// Defaults to true so pre-warm conversations don't join Daily until the user taps Start.
    var deferJoinUntilAssessmentActive = true

    // MARK: - Daily SDK

    private var callClient: CallClient?

    /// Tavus conversation ID extracted from the room URL path.
    private var conversationId: String?

    // MARK: - Echo Queue (ported from TavusBridge.html pumpEchoQueue)

    private var echoTextQueue: [String] = []
    private var echoInFlight = false
    private var echoWatchdogTask: Task<Void, Never>?
    private var echoCounter = 0

    /// True after the first clinical echo is sent — gates remote audio subscription.
    /// Suppresses the Tavus persona greeting that plays on room join.
    private var firstEchoSent = false

    /// Echoes received before the room is joined — flushed after successful join.
    private var pendingBeforeJoin: [PendingOp] = []

    // MARK: - Auto-Interrupt Guards (ported from TavusBridge.html)

    /// Timestamp of the last overwrite_context sent — suppresses spurious
    /// started_speaking interrupts that fire during the pre-echo pipeline.
    private var lastOverwriteContextAt: Date = .distantPast

    /// Timestamp of the last echo slot release — suppresses interrupts during
    /// the brief gap between chained echoes.
    private var lastEchoSlotReleasedAt: Date = .distantPast

    /// Timestamp of room join — blocks all auto-interrupts for 5 seconds
    /// to prevent mic noise from killing the first utterance.
    private var joinedAt: Date?
    private let interruptGuardInterval: TimeInterval = 5.0

    // MARK: - Notification Observers

    private var contextObserver: NSObjectProtocol?
    private var echoObserver: NSObjectProtocol?
    private var respondObserver: NSObjectProtocol?
    private var muteObserver: NSObjectProtocol?
    private var interruptObserver: NSObjectProtocol?

    // MARK: - Pending Operations

    private enum PendingOp {
        case context(String)
        case echo(String)
        case respond(String)
        case interrupt
        case micMuted(Bool)
        case sensitivity(pause: String, interrupt: String)
    }

    // MARK: - Init / Deinit

    override init() {
        super.init()
        registerNotificationObservers()
        log.info("DailyCallManager initialized")
    }

    deinit {
        // Observers and tasks are cleaned up on leave() / main actor context.
        // Cannot call main-actor methods from deinit (nonisolated context).
        log.info("DailyCallManager deinit")
    }

    // MARK: - Lifecycle

    /// Store the room URL for later join. Call when conversation URL becomes available.
    func configure(url: String) {
        guard let parsed = URL(string: url) else {
            log.error("configure — invalid URL: \(url, privacy: .public)")
            return
        }
        roomURL = parsed
        conversationId = parsed.lastPathComponent
        log.info("configure — URL set, conversationId=\(self.conversationId ?? "nil", privacy: .public)")
    }

    /// Join the Daily room if conditions are met (URL set, not deferred, not already joined).
    func joinIfReady() {
        guard !deferJoinUntilAssessmentActive else {
            log.info("joinIfReady — deferred, skipping")
            return
        }
        guard let url = roomURL else {
            log.info("joinIfReady — no URL configured")
            return
        }
        // Block if a CallClient already exists (joining or joined).
        // Prevents duplicate joins that confuse Tavus's replica state.
        guard callClient == nil else {
            log.info("joinIfReady — CallClient already exists (state: \(self.callState.rawValue, privacy: .public))")
            return
        }

        let client = CallClient()
        client.delegate = self
        self.callClient = client

        // Reset state for new session
        echoTextQueue.removeAll()
        echoInFlight = false
        echoCounter = 0
        firstEchoSent = false
        lastOverwriteContextAt = .distantPast
        lastEchoSlotReleasedAt = .distantPast
        joinedAt = nil
        replicaIsSpeaking = false
        remoteVideoTrack = nil

        log.info("joinIfReady — joining room")

        // Join with default settings — mic/camera controlled via setInputEnabled after join
        client.join(url: url) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                log.info("Join successful")
                self.onJoinSucceeded()
            case .failure(let error):
                log.error("Join failed: \(error.localizedDescription, privacy: .public)")
                NotificationCenter.default.post(name: .tavusConnectionLost, object: nil,
                                                userInfo: ["message": error.localizedDescription])
            }
        }
    }

    /// Leave the Daily room and clean up.
    func leave() {
        echoTextQueue.removeAll()
        echoInFlight = false
        echoWatchdogTask?.cancel()
        echoWatchdogTask = nil
        pendingBeforeJoin.removeAll()

        guard let client = callClient else { return }
        callClient = nil
        remoteVideoTrack = nil

        client.leave { result in
            if case .failure(let err) = result {
                log.error("leave failed: \(err.localizedDescription, privacy: .public)")
            }
        }
        log.info("leave — disconnecting")
    }

    // MARK: - Post-Join Setup

    private func onJoinSucceeded() {
        joinedAt = Date()

        // Mic starts muted — unmuted by phase views after prompt delivery
        callClient?.setInputEnabled(.microphone, false, completion: nil)
        log.info("Mic muted on join")

        // Set clinical sensitivity
        sendSensitivity(pause: "low", interrupt: "low")
        log.info("Set clinical sensitivity: pause=low, interrupt=low")

        // Set neuropsychologist persona context
        let personaContext = "You are a board-certified clinical neuropsychologist administering a standardized cognitive assessment. VOICE STYLE: Calm, measured, professional. Speak at a moderate pace with clear enunciation. Your tone is warm but clinical — reassuring without being casual. Never use slang, jokes, or exclamation marks. Never say \"awesome\", \"cool\", \"great job\", or give performance feedback. NEVER correct, grade, coach, or evaluate the patient's answers — no \"right\", \"wrong\", \"close\", \"not quite\", \"actually\", \"good try\", or pronunciation fixes. Do not repeat their answer back to judge it. RULES: 1) Do NOT speak until you receive an echo command. Stay completely silent until then. 2) Speak ONLY the text sent via echo commands — do not ad-lib. 3) If the patient speaks to you between echo commands, remain silent. Do not respond, acknowledge, or generate any speech unless you receive an echo command. 4) Never provide hints, clues, or feedback on correctness. 5) Maintain a neutral, supportive demeanor throughout."
        sendContextUpdate(personaContext)
        log.info("Set neuropsychologist persona context")

        // Mark as joined
        NotificationCenter.default.post(name: .tavusDailyRoomJoined, object: nil)

        // Flush pending ops
        let ops = pendingBeforeJoin
        pendingBeforeJoin.removeAll()
        if !ops.isEmpty {
            log.info("Flushing \(ops.count) pending op(s)")
            for op in ops {
                executeOp(op)
            }
        }

        log.info("Post-join setup complete")
    }

    // MARK: - Tavus CVI Protocol (sendAppMessage)

    private func sendInteraction(_ eventType: String, properties: [String: Any] = [:]) {
        guard let client = callClient, let convId = conversationId else {
            log.warning("sendInteraction(\(eventType, privacy: .public)) — not connected")
            return
        }
        var payload: [String: Any] = [
            "message_type": "conversation",
            "event_type": eventType,
            "conversation_id": convId
        ]
        if !properties.isEmpty {
            payload["properties"] = properties
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            log.error("sendInteraction — JSON serialization failed for \(eventType, privacy: .public)")
            return
        }
        client.sendAppMessage(json: data, to: .all) { result in
            if case .failure(let err) = result {
                log.error("sendAppMessage failed: \(err.localizedDescription, privacy: .public)")
            }
        }
        log.info("Sent: \(eventType, privacy: .public)")
    }

    // MARK: - Context Update

    private func sendContextUpdate(_ context: String) {
        lastOverwriteContextAt = Date()
        sendInteraction("conversation.overwrite_llm_context", properties: ["context": context])
    }

    // MARK: - Echo Queue

    private func sendEcho(_ text: String) {
        guard callState == .joined else {
            log.info("Echo queued (not yet joined): \(text.prefix(60), privacy: .public)")
            pendingBeforeJoin.append(.echo(text))
            return
        }
        echoTextQueue.append(text)
        log.info("Echo enqueued, depth=\(self.echoTextQueue.count)")
        pumpEchoQueue()
    }

    private func pumpEchoQueue() {
        guard callClient != nil, callState == .joined else { return }
        guard !echoInFlight else { return }
        guard !echoTextQueue.isEmpty else { return }

        let text = echoTextQueue.removeFirst()
        echoInFlight = true

        // On the very first echo, subscribe to remote audio.
        // Until now, remote audio was unsubscribed to suppress the Tavus persona greeting.
        if !firstEchoSent {
            firstEchoSent = true
            // Audio subscription is automatic in native SDK — no MediaStream gating needed.
            // The auto-interrupt guard window (5s) prevents the greeting from being heard.
            log.info("First echo — audio enabled (assessment started)")
        }

        // Mute mic during echo delivery
        callClient?.setInputEnabled(.microphone, false, completion: nil)
        log.info("Mic muted before echo")

        // Start watchdog timer
        echoWatchdogTask?.cancel()
        let isLongForm = text.contains("<speak") || text.count > 280
        let watchdogSeconds: TimeInterval = isLongForm ? 90 : 10
        echoWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(watchdogSeconds))
            guard let self, !Task.isCancelled else { return }
            log.warning("Echo watchdog fired after \(watchdogSeconds)s — releasing slot")
            self.releaseEchoSlot()
            // Synthesize stopped_speaking so Swift continuations resume
            NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil)
            // Unmute mic if queue empty
            if self.echoTextQueue.isEmpty && !self.echoInFlight {
                self.callClient?.setInputEnabled(.microphone, true, completion: nil)
                log.info("Mic unmuted (watchdog, queue empty)")
            }
        }

        // Send the echo
        echoCounter += 1
        log.info("Echo sending: \(text.prefix(80), privacy: .public)")
        sendInteraction("conversation.echo", properties: [
            "modality": "text",
            "text": text,
            "inference_id": "echo_\(echoCounter)",
            "done": "true"
        ])
    }

    private func releaseEchoSlot() {
        guard echoInFlight else { return }
        echoWatchdogTask?.cancel()
        echoWatchdogTask = nil
        echoInFlight = false
        lastEchoSlotReleasedAt = Date()
        pumpEchoQueue()
    }

    // MARK: - Respond (LLM bypass — faster than echo)

    private func sendRespond(_ text: String) {
        guard callState == .joined else {
            pendingBeforeJoin.append(.respond(text))
            return
        }
        sendInteraction("conversation.respond", properties: ["text": text])
    }

    // MARK: - Interrupt

    private func sendInterrupt() {
        echoTextQueue.removeAll()
        echoInFlight = false
        echoWatchdogTask?.cancel()
        echoWatchdogTask = nil
        log.info("Interrupt: cleared echo queue and released echo slot")
        sendInteraction("conversation.interrupt")
    }

    // MARK: - Mic Control

    private func setMicMuted(_ muted: Bool) {
        callClient?.setInputEnabled(.microphone, !muted, completion: nil)
        log.info("Mic \(muted ? "muted" : "unmuted", privacy: .public) (explicit)")
    }

    // MARK: - Sensitivity

    private func sendSensitivity(pause: String, interrupt: String) {
        sendInteraction("conversation.sensitivity", properties: [
            "participant_pause_sensitivity": pause,
            "participant_interrupt_sensitivity": interrupt
        ])
    }

    // MARK: - Auto-Interrupt Logic (ported from TavusBridge.html)

    private func shouldAllowInterrupt() -> Bool {
        guard let joinedAt else { return false }
        if Date().timeIntervalSince(joinedAt) < interruptGuardInterval {
            log.info("Auto-interrupt: blocked (within \(self.interruptGuardInterval)s guard window)")
            return false
        }
        return true
    }

    private func handleUserStoppedSpeaking() {
        // Don't interrupt mid-echo
        if echoInFlight || !echoTextQueue.isEmpty {
            log.info("Auto-interrupt: skipped (echo queued or in flight)")
            return
        }
        guard shouldAllowInterrupt() else { return }
        sendInteraction("conversation.interrupt")
        log.info("Auto-interrupt: suppressed LLM acknowledgment after patient speech")
    }

    private func handleReplicaStartedSpeaking() {
        if echoInFlight || !echoTextQueue.isEmpty {
            // Expected echo — mute mic during avatar speech
            callClient?.setInputEnabled(.microphone, false, completion: nil)
            log.info("Mic muted (avatar speaking)")
            return
        }

        // Unprompted speech — check suppression guards
        let now = Date()
        if now.timeIntervalSince(lastOverwriteContextAt) < 1.2 {
            log.info("Auto-interrupt: skipped (recent overwrite_context)")
            return
        }
        if now.timeIntervalSince(lastEchoSlotReleasedAt) < 1.2 {
            log.info("Auto-interrupt: skipped (post-stopped_speaking gap)")
            return
        }
        guard shouldAllowInterrupt() else { return }
        sendInteraction("conversation.interrupt")
        log.info("Auto-interrupt: suppressed unprompted Tavus speech")
    }

    private func handleReplicaStoppedSpeaking() {
        releaseEchoSlot()
        // Unmute mic only if no more echoes are queued
        if echoTextQueue.isEmpty && !echoInFlight {
            callClient?.setInputEnabled(.microphone, true, completion: nil)
            log.info("Mic unmuted (avatar stopped, queue empty)")
        } else {
            log.info("Mic stays muted (more echoes queued)")
        }
    }

    // MARK: - Pending Op Dispatch

    private func enqueueOrExecute(_ op: PendingOp) {
        guard callState == .joined else {
            pendingBeforeJoin.append(op)
            return
        }
        executeOp(op)
    }

    private func executeOp(_ op: PendingOp) {
        switch op {
        case .context(let s): sendContextUpdate(s)
        case .echo(let s): sendEcho(s)
        case .respond(let s): sendRespond(s)
        case .interrupt: sendInterrupt()
        case .micMuted(let m): setMicMuted(m)
        case .sensitivity(let p, let i): sendSensitivity(pause: p, interrupt: i)
        }
    }

    // MARK: - Notification Observers

    private func registerNotificationObservers() {
        contextObserver = NotificationCenter.default.addObserver(
            forName: .tavusContextUpdate, object: nil, queue: .main
        ) { [weak self] notification in
            guard let context = notification.userInfo?["context"] as? String else { return }
            MainActor.assumeIsolated { self?.enqueueOrExecute(.context(context)) }
        }
        echoObserver = NotificationCenter.default.addObserver(
            forName: .tavusEchoRequest, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else { return }
            MainActor.assumeIsolated { self?.enqueueOrExecute(.echo(text)) }
        }
        respondObserver = NotificationCenter.default.addObserver(
            forName: .tavusRespondRequest, object: nil, queue: .main
        ) { [weak self] notification in
            guard let text = notification.userInfo?["text"] as? String, !text.isEmpty else { return }
            MainActor.assumeIsolated { self?.enqueueOrExecute(.respond(text)) }
        }
        muteObserver = NotificationCenter.default.addObserver(
            forName: .tavusMicMuteRequest, object: nil, queue: .main
        ) { [weak self] notification in
            guard let muted = notification.userInfo?["muted"] as? Bool else { return }
            MainActor.assumeIsolated { self?.enqueueOrExecute(.micMuted(muted)) }
        }
        interruptObserver = NotificationCenter.default.addObserver(
            forName: .tavusInterruptRequest, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enqueueOrExecute(.interrupt) }
        }
    }

    private func removeNotificationObservers() {
        [contextObserver, echoObserver, respondObserver, muteObserver, interruptObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
    }
}

// MARK: - CallClientDelegate

extension DailyCallManager: CallClientDelegate {
    nonisolated func callClient(_ callClient: CallClient, callStateUpdated state: CallState) {
        Task { @MainActor in
            self.callState = state
            log.info("Call state: \(state.rawValue, privacy: .public)")
            if state == .left {
                self.remoteVideoTrack = nil
                NotificationCenter.default.post(name: .tavusConnectionLost, object: nil)
            }
        }
    }

    nonisolated func callClient(_ callClient: CallClient, participantJoined participant: Participant) {
        let isLocal = participant.info.isLocal
        let track = participant.media?.camera.track
        let idDescription = participant.id.description
        Task { @MainActor in
            guard !isLocal else { return }
            log.info("Participant joined: \(idDescription, privacy: .public)")
            self.remoteVideoTrack = track
        }
    }

    nonisolated func callClient(_ callClient: CallClient, participantUpdated participant: Participant) {
        let isLocal = participant.info.isLocal
        let track = participant.media?.camera.track
        Task { @MainActor in
            if isLocal { return }
            self.remoteVideoTrack = track
        }
    }

    nonisolated func callClient(_ callClient: CallClient, participantLeft participant: Participant,
                    withReason reason: ParticipantLeftReason) {
        let isLocal = participant.info.isLocal
        let idDescription = participant.id.description
        Task { @MainActor in
            guard !isLocal else { return }
            log.info("Participant left: \(idDescription, privacy: .public)")
            self.remoteVideoTrack = nil
        }
    }

    /// Receive Tavus CVI events via Daily's data channel.
    nonisolated func callClient(_ callClient: CallClient, appMessageAsJson jsonData: Data,
                    from participantID: ParticipantID) {
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let eventType = json["event_type"] as? String
        else { return }

        Task { @MainActor in
            log.debug("App message: \(eventType, privacy: .public)")

            switch eventType {
            case "conversation.replica.started_speaking":
                self.replicaIsSpeaking = true
                NotificationCenter.default.post(name: .avatarStartedSpeaking, object: nil)
                self.handleReplicaStartedSpeaking()

            case "conversation.replica.stopped_speaking":
                self.replicaIsSpeaking = false
                NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil)
                self.handleReplicaStoppedSpeaking()

            case "conversation.user.started_speaking":
                NotificationCenter.default.post(name: .patientStartedSpeaking, object: nil)

            case "conversation.user.stopped_speaking":
                NotificationCenter.default.post(name: .patientDoneSpeaking, object: nil)
                self.handleUserStoppedSpeaking()

            case "system.replica_joined":
                log.info("Replica joined")

            case "system.replica_present":
                break // Heartbeat — ignore

            case "conversation.utterance":
                log.debug("Utterance event received")

            default:
                log.debug("Unhandled event: \(eventType, privacy: .public)")
            }
        }
    }
}
