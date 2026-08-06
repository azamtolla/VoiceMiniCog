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

/// os_signpost log — Instruments captures phase transitions, echo spans, and
/// turn-state changes under this category without perturbing the main log
/// stream. Signposts are cheap when Instruments isn't attached.
private let signposter = OSSignposter(
    subsystem: "com.mercycog.VoiceMiniCog",
    category: "DailyCall.signpost"
)

/// Pure decision for whether `handleUserStoppedSpeaking` should fire the
/// auto-interrupt + LLM drain. Extracted so the decision logic can be
/// unit-tested without spinning up a CallClient or a full Tavus session.
///
/// Rules (in order — first match wins):
///   1. If an echo is in flight or queued → skip (`echo-conflict`):
///      interrupting would drop a clinical prompt mid-speech.
///   2. If the post-join guard window hasn't elapsed → skip (`join-guard`):
///      avoids killing the first utterance to mic noise at join time.
///   3. If the current phase is a scripted subtest → skip (`phase-gated`):
///      scripted phases run with speculative_inference OFF on the persona,
///      so the drain is unnecessary and its `overwrite_llm_context` can
///      clobber a just-finished user response that the UI is still scoring.
///   4. If the utterance duration was below the min threshold → skip
///      (`below-min-duration`): a cough / "umm" / stray VAD should never
///      drain the LLM context.
///   5. Otherwise → fire the interrupt + context-clobber.
enum AutoInterruptDecision: Equatable {
    case fire(reason: String)
    case skip(reason: String)

    static func decide(
        echoInFlight: Bool,
        queueDepth: Int,
        allowInterrupt: Bool,
        isScriptedPhase: Bool,
        utteranceDuration: TimeInterval,
        minDurationForInterrupt: TimeInterval
    ) -> AutoInterruptDecision {
        if echoInFlight || queueDepth > 0 {
            return .skip(reason: "echo-conflict")
        }
        if !allowInterrupt {
            return .skip(reason: "join-guard")
        }
        if isScriptedPhase {
            return .skip(reason: "phase-gated")
        }
        if utteranceDuration < minDurationForInterrupt {
            return .skip(reason: "below-min-duration")
        }
        return .fire(reason: "user-driven")
    }

    /// Map a skip reason to the downstream "response marked" classification
    /// for log/observability. Mirrors the taxonomy in the user's debug spec.
    static func responseMark(for skipReason: String) -> String {
        switch skipReason {
        case "echo-conflict":        return "ignored"
        case "join-guard":           return "final"
        case "phase-gated":          return "final"
        case "below-min-duration":   return "partial"
        default:                     return "unknown"
        }
    }
}

@MainActor @Observable
final class DailyCallManager: NSObject {

    // MARK: - Published State

    /// Remote participant's (Tavus replica) video track for DailyVideoView binding.
    var remoteVideoTrack: VideoTrack?

    /// Current call state — .initialized, .joined, .left
    var callState: CallState = .initialized

    /// True when the replica is actively speaking an echo.
    var replicaIsSpeaking = false

    /// True while the patient is speaking (driven by Tavus user.started/stopped_speaking).
    /// Observable so patient-facing views can render a live waveform indicator.
    var patientIsSpeaking = false

    /// Reason the session ended, mapped from `system.shutdown` events.
    /// nil while session is active. Drives which score flow the report uses.
    var shutdownReason: SessionShutdownReason?

    // MARK: - Configuration

    /// Stored room URL for deferred join pattern (Home pre-warm).
    @ObservationIgnored private var roomURL: URL?

    /// When true, `joinIfReady()` is a no-op — delays join until assessment starts.
    /// Defaults to true so pre-warm conversations don't join Daily until the user taps Start.
    @ObservationIgnored var deferJoinUntilAssessmentActive = true

    // MARK: - Daily SDK

    @ObservationIgnored private var callClient: CallClient?

    /// True while an async `join(url:)` is in flight but has not yet
    /// completed (success or failure). Prevents duplicate joins that the
    /// `callClient == nil` guard alone can't catch — there's a window
    /// between "CallClient created" and "Daily SDK finishes signaling
    /// handshake" where `callClient != nil` but state is not yet `.joined`.
    /// A second caller hitting `joinIfReady()` during that window would
    /// create a second CallClient, causing the Daily SDK's
    /// "maximum number of subscriptions (1) are already in progress"
    /// warning observed in the logs.
    @ObservationIgnored private var joinInProgress = false

    /// Tavus conversation ID extracted from the room URL path.
    @ObservationIgnored private var conversationId: String?

    // MARK: - Echo Queue (ported from TavusBridge.html pumpEchoQueue)

    @ObservationIgnored private var echoTextQueue: [String] = []
    @ObservationIgnored private var echoInFlight = false
    @ObservationIgnored private var echoWatchdogTask: Task<Void, Never>?
    @ObservationIgnored private var echoCounter = 0

    // Diagnostic: timestamp + identity of the in-flight echo, plus running
    // count of stopped/started cycles within a single echo. If Tavus emits
    // multiple stopped_speaking events for one SSML block, that's the audio-
    // glitch / mic-cycling root-cause signal.
    @ObservationIgnored private var inFlightEchoStartedAt: Date?
    @ObservationIgnored private var inFlightEchoText: String = ""
    @ObservationIgnored private var inFlightEchoSpeakingCycles: Int = 0
    @ObservationIgnored private var inFlightEchoTokensSinceSent: Int = 0
    /// Per-echo one-shot: if the LLM starts streaming tokens before the
    /// replica actually starts speaking, we treat the echo as "collided"
    /// and fire one recovery cycle (interrupt + re-queue). Resets on each
    /// new echo send; cleared once replica.started_speaking arrives.
    @ObservationIgnored private var echoCollisionRecoveryTask: Task<Void, Never>?
    @ObservationIgnored private var echoCollisionRecoveryFired: Bool = false

    /// True after the first clinical echo is sent — gates remote audio subscription.
    /// Suppresses the Tavus persona greeting that plays on room join.
    @ObservationIgnored private var firstEchoSent = false

    /// Echoes received before the room is joined — flushed after successful join.
    @ObservationIgnored private var pendingBeforeJoin: [PendingOp] = []

    // MARK: - Auto-Interrupt Guards (ported from TavusBridge.html)

    /// Timestamp of the last overwrite_context sent — suppresses spurious
    /// started_speaking interrupts that fire during the pre-echo pipeline.
    @ObservationIgnored private var lastOverwriteContextAt: Date = .distantPast

    /// Timestamp of the last echo slot release — suppresses interrupts during
    /// the brief gap between chained echoes.
    @ObservationIgnored private var lastEchoSlotReleasedAt: Date = .distantPast

    /// Timestamp of room join — blocks all auto-interrupts for 5 seconds
    /// to prevent mic noise from killing the first utterance.
    @ObservationIgnored private var joinedAt: Date?
    @ObservationIgnored private let interruptGuardInterval: TimeInterval = 5.0

    // MARK: - Session Abandonment Watchdog
    //
    // Autonomous-operation safety net. Patient is alone with the iPad, so we
    // detect and recover when they wander off, fall silent, or disengage.
    //
    // State machine:
    //   user.started_speaking                      -> silenceStartedAt = nil (cancel timers)
    //   beginSilenceWatch() (phase-view enters listen) -> arm 90s + 150s timers
    //   90s elapsed  -> sendEcho("Are you still there? Take your time.")
    //   150s elapsed -> endConversation + post .sessionAbandoned

    @ObservationIgnored private var silenceStartedAt: Date?
    @ObservationIgnored private var reengagementTask: Task<Void, Never>?
    @ObservationIgnored private var abandonmentTask: Task<Void, Never>?
    @ObservationIgnored private let reengagementAfter: TimeInterval = 90.0
    @ObservationIgnored private let abandonmentAfter: TimeInterval = 150.0
    @ObservationIgnored private var reengagementPromptSent = false

    // MARK: - Event Ordering (seq / turn_idx)
    //
    // Tavus ships `seq` (monotonic) and `turn_idx` (turn group) on every event.
    // We log out-of-order delivery and expose turn_idx so phase views can key
    // off avatar-turn completion instead of wall-clock timing.

    @ObservationIgnored private var lastObservedSeq: Int = -1
    @ObservationIgnored private(set) var currentTurnIdx: Int = -1

    // MARK: - Phase Scoping (speculative_inference toggle)

    /// Current assessment phase type. Drives whether `speculative_inference`
    /// is pushed to the LLM layer via `conversation.overwrite_llm_context`.
    @ObservationIgnored private(set) var currentPhase: AssessmentPhaseType = .intro
    @ObservationIgnored private var lastSpeculativeSetting: Bool?

    // MARK: - User Utterance Timing (min-duration gate)

    /// Timestamp of the most recent `conversation.user.started_speaking` event.
    /// Used by `handleUserStoppedSpeaking` to gate auto-interrupt on a
    /// minimum utterance duration — avoids killing the LLM context on
    /// coughs, brief fillers, or stray VAD triggers.
    @ObservationIgnored private var userStartedSpeakingAt: Date?

    /// Minimum user-utterance duration before auto-interrupt may fire.
    /// <1200ms is typical of coughs, "umm", "eh" — treating those as
    /// interruptible responses was clobbering valid partial transcripts
    /// during word recall / orientation.
    @ObservationIgnored private let minUtteranceDurationForInterrupt: TimeInterval = 1.2

    // MARK: - Notification Observers

    @ObservationIgnored private var contextObserver: NSObjectProtocol?
    @ObservationIgnored private var echoObserver: NSObjectProtocol?
    @ObservationIgnored private var respondObserver: NSObjectProtocol?
    @ObservationIgnored private var muteObserver: NSObjectProtocol?
    @ObservationIgnored private var interruptObserver: NSObjectProtocol?
    @ObservationIgnored private var beginSilenceObserver: NSObjectProtocol?
    @ObservationIgnored private var cancelSilenceObserver: NSObjectProtocol?
    @ObservationIgnored private var phaseTypeObserver: NSObjectProtocol?

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
    }

    // MARK: - Lifecycle

    /// Store the room URL for later join. Call when conversation URL becomes available.
    ///
    /// Edge-triggered: after URL is set, this synchronously calls `joinIfReady()`
    /// so callers never need to remember to sequence `configure` + `joinIfReady`
    /// manually. Previously the join relied on a polling path in
    /// `TavusCVIView.Coordinator.attemptJoinIfPossible()`, which produced the
    /// "joinIfReady — no URL configured" then later "URL arrived" log sequence
    /// observed in the crash evidence. `joinIfReady` is idempotent via the
    /// `joinInProgress` and `callClient != nil` guards, so calling it from both
    /// `configure` AND existing call sites is safe.
    func configure(url: String) {
        guard let parsed = URL(string: url) else {
            log.error("configure — invalid URL: \(url, privacy: .public)")
            return
        }
        roomURL = parsed
        conversationId = parsed.lastPathComponent
        log.info("configure — URL set, conversationId=\(self.conversationId ?? "nil", privacy: .public) — edge-triggering joinIfReady")
        joinIfReady()
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
        // Block if a join is mid-flight. The SDK creates the CallClient
        // synchronously but signaling + media subscription are async; in
        // that window a second entry into joinIfReady would otherwise
        // create a second CallClient and stack a second subscription
        // attempt, tripping the Daily SDK "max subscriptions (1) in
        // progress" guard observed in the logs.
        guard !joinInProgress else {
            log.info("joinIfReady — join already in progress, skipping")
            return
        }

        let client = CallClient()
        client.delegate = self
        self.callClient = client
        self.joinInProgress = true

        // Reset state for new session
        echoTextQueue.removeAll()
        echoInFlight = false
        echoCounter = 0
        firstEchoSent = false
        lastMicEnabledDispatched = nil
        lastOverwriteContextAt = .distantPast
        lastEchoSlotReleasedAt = .distantPast
        joinedAt = nil
        replicaIsSpeaking = false
        remoteVideoTrack = nil
        patientIsSpeaking = false
        shutdownReason = nil
        currentPhase = .intro
        lastSpeculativeSetting = nil
        lastObservedSeq = -1
        currentTurnIdx = -1
        userStartedSpeakingAt = nil
        cancelSilenceWatch()

        log.info("joinIfReady — joining room")

        // Krisp noise cancellation: NOT exposed by Daily iOS SDK v0.37.0.
        // AudioMediaTrackSettings only carries deviceID. Client-side Krisp
        // is a daily-js feature. Equivalent server-side mitigations already
        // in place: Tavus persona layer.conversational_flow.voice_isolation
        // (see TavusService.desiredConversationalFlow) provides upstream
        // ambient-noise isolation via Tavus's audio pipeline.
        //
        // TODO(BAA+SDK-upgrade): When Daily iOS exposes AudioProcessorSettings,
        // enable Krisp at aggressiveness=low here (exam rooms are noisy, but
        // MCI speech can be quiet — default "high" suppresses it).
        client.join(url: url) { [weak self] result in
            // Daily's completion may run on a background thread — hop to MainActor.
            Task { @MainActor in
                guard let self else { return }
                // Always clear join-in-progress when the async join resolves,
                // whether success or failure. On failure the CallClient
                // reference is dropped below so a subsequent joinIfReady
                // can retry cleanly.
                self.joinInProgress = false
                switch result {
                case .success:
                    log.info("Join successful")
                    self.onJoinSucceeded()
                case .failure(let error):
                    log.error("Join failed: \(error.localizedDescription, privacy: .public)")
                    // Drop the half-initialized CallClient so retry is possible.
                    self.callClient = nil
                    NotificationCenter.default.post(name: .tavusConnectionLost, object: nil,
                                                    userInfo: ["message": error.localizedDescription])
                }
            }
        }
    }

    /// Leave the Daily room and clean up.
    func leave() {
        echoTextQueue.removeAll()
        echoInFlight = false
        echoWatchdogTask?.cancel()
        echoWatchdogTask = nil
        cancelMicUnmuteSafety()
        lastMicEnabledDispatched = nil
        pendingBeforeJoin.removeAll()
        joinInProgress = false
        cancelSilenceWatch()
        lastObservedSeq = -1
        currentTurnIdx = -1
        lastSpeculativeSetting = nil
        // currentPhase intentionally preserved across leave so post-leave
        // flows (report generation) can inspect the last phase the patient
        // reached. It resets to .intro on the next joinIfReady().
        patientIsSpeaking = false

        guard let client = callClient else { return }
        callClient = nil
        remoteVideoTrack = nil

        client.leave { result in
            Task { @MainActor in
                if case .failure(let err) = result {
                    log.error("leave failed: \(err.localizedDescription, privacy: .public)")
                }
            }
        }
        log.info("leave — disconnecting")
    }

    // MARK: - Post-Join Setup

    /// Dispatches a Daily FFI `setInputEnabled` call in a way that avoids a
    /// priority inversion on MainActor.
    ///
    /// `CallClient.setInputEnabled` is `@MainActor`-isolated, so it must run on
    /// main. The completion-based variant synchronously acquires Daily's Rust
    /// `RwLock` — if that lock is held by a Default-QoS worker, MainActor
    /// (user-interactive QoS) blocks waiting on a lower-QoS thread, tripping
    /// Thread Performance Checker.
    ///
    /// Using the `async throws` variant instead lets MainActor *suspend*
    /// (freeing the thread to run other work and allowing QoS propagation
    /// through the awaiting continuation) rather than *block* synchronously on
    /// the lock. Dispatching via a child `Task` also breaks the synchronous
    /// call chain from the delegate/event handler.
    ///
    /// Ordering is preserved because each Task is spawned from MainActor in
    /// source order; Daily's SDK serializes FFI calls internally, and the
    /// `await` point only suspends after the call has been enqueued to the
    /// SDK's internal worker.
    /// Last mic input-enabled state we actually dispatched to the SDK.
    /// Used to skip redundant `setInputEnabled` calls, which swap the
    /// cam-audio MediaStreamTrack and trigger a brief audio-session
    /// reconfiguration — audible as a pop/click in the avatar's audio.
    @ObservationIgnored private var lastMicEnabledDispatched: Bool?

    /// Safety-net task that force-unmutes the mic if it has remained muted
    /// past the expected "avatar finished speaking → listening" handoff.
    /// Armed in `handleReplicaStoppedSpeaking`, cancelled when the next echo
    /// starts OR when the patient begins speaking.
    @ObservationIgnored private var micUnmuteSafetyTask: Task<Void, Never>?

    /// Hard ceiling after the last replica.stopped_speaking before we force
    /// the mic open. Short enough that patients don't start responding to
    /// dead-air; long enough that a fast follow-up echo (echo chain) doesn't
    /// flap the mic on/off.
    @ObservationIgnored private let micUnmuteSafetyWindow: TimeInterval = 0.4

    /// Reset the `lastMicEnabledDispatched` cache and re-issue whatever the
    /// caller last requested. Used when the underlying audio session route
    /// changes (AVAudioSession .routeChange) — after a route swap the
    /// cached dispatched-state no longer reflects SDK reality.
    func invalidateMicStateCache() {
        log.info("Mic state cache invalidated (audio route change)")
        lastMicEnabledDispatched = nil
    }

    private func setMicrophoneInputEnabledOffMain(client: CallClient, enabled: Bool) {
        // Skip no-op mute/unmute calls. Without this, a single echo
        // delivery issues setInputEnabled(false) up to 3× (explicit
        // pre-echo mute, replica.started_speaking safety mute, and any
        // subsequent cycle) — each one swaps the MediaStreamTrack and
        // can glitch the audio output.
        if lastMicEnabledDispatched == enabled { return }
        lastMicEnabledDispatched = enabled
        log.debug("Mic device transition -> \(enabled ? "enabled" : "disabled", privacy: .public)")
        Task { @MainActor in
            do {
                try await client.setInputEnabled(.microphone, enabled)
            } catch {
                log.error("setInputEnabled(microphone, \(enabled, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                // Dispatch failed — allow next call to retry by clearing
                // the cached state. Otherwise a transient SDK error could
                // strand the mic in the opposite state forever.
                if self.lastMicEnabledDispatched == enabled {
                    self.lastMicEnabledDispatched = nil
                }
            }
        }
    }

    private func onJoinSucceeded() {
        joinedAt = Date()

        // Mic starts muted — unmuted by phase views after prompt delivery
        if let client = callClient {
            setMicrophoneInputEnabledOffMain(client: client, enabled: false)
        }
        log.info("Mic muted on join")

        // Set clinical sensitivity
        sendSensitivity(pause: "low", interrupt: "low")
        log.info("Set clinical sensitivity: pause=low, interrupt=low")

        // Set neuropsychologist persona context with clinical guardrails appended.
        let baseContext = "You are a board-certified clinical neuropsychologist administering a standardized cognitive assessment. VOICE STYLE: Calm, measured, professional. Speak at a moderate pace with clear enunciation. Your tone is warm but clinical — reassuring without being casual. Never use slang, jokes, or exclamation marks. Never say \"awesome\", \"cool\", \"great job\", or give performance feedback. NEVER correct, grade, coach, or evaluate the patient's answers — no \"right\", \"wrong\", \"close\", \"not quite\", \"actually\", \"good try\", or pronunciation fixes. Do not repeat their answer back to judge it. RULES: 1) Do NOT speak until you receive an echo command. Stay completely silent until then. 2) Speak ONLY the text sent via echo commands — do not ad-lib. 3) If the patient speaks to you between echo commands, remain silent. Do not respond, acknowledge, or generate any speech unless you receive an echo command. 4) Never provide hints, clues, or feedback on correctness. 5) Maintain a neutral, supportive demeanor throughout."
        let personaContext = baseContext + "\n\n" + TavusService.personaGuardrails
        sendContextUpdate(personaContext)
        log.info("Set neuropsychologist persona context + guardrails (len=\(personaContext.count))")

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
            Task { @MainActor in
                if case .failure(let err) = result {
                    log.error("sendAppMessage failed: \(err.localizedDescription, privacy: .public)")
                }
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
        if let client = callClient {
            setMicrophoneInputEnabledOffMain(client: client, enabled: false)
        }
        log.info("Mic muted before echo")

        // Start watchdog timer.
        // Prior logic: isLongForm (SSML || >280 chars) → 90s, else 10s.
        // The 10s bucket was catching medium-length plain-text prompts like
        // "Earlier, I read you some words and asked you to hold onto them..."
        // (192 chars, ~11s actual TTS time) and firing mid-speech, unmuting
        // the mic and posting a premature avatarDoneSpeaking. Graduate by
        // length so medium prompts get room to breathe.
        echoWatchdogTask?.cancel()
        let isSSML = text.contains("<speak")
        let charCount = text.count
        let watchdogSeconds: TimeInterval
        if isSSML || charCount > 280 {
            watchdogSeconds = 90
        } else if charCount > 100 {
            // Plain-text but medium-length (orientation prompts, recall
            // prompts). TTS ~150 wpm → give ~15–25s of headroom.
            watchdogSeconds = 25
        } else {
            // Short one-liners ("What year is this?") — 12s is plenty.
            watchdogSeconds = 12
        }
        echoWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(watchdogSeconds))
            guard let self, !Task.isCancelled else { return }
            log.warning("Echo watchdog fired after \(watchdogSeconds)s — releasing slot")
            self.releaseEchoSlot()
            // Synthesize stopped_speaking so Swift continuations resume
            NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil)
            // Unmute mic if queue empty
            if self.echoTextQueue.isEmpty && !self.echoInFlight {
                if let client = self.callClient {
                    self.setMicrophoneInputEnabledOffMain(client: client, enabled: true)
                }
                log.info("Mic unmuted (watchdog, queue empty)")
            }
        }

        // Send the echo
        echoCounter += 1
        inFlightEchoStartedAt = Date()
        inFlightEchoText = text
        inFlightEchoSpeakingCycles = 0
        inFlightEchoTokensSinceSent = 0
        echoCollisionRecoveryFired = false
        log.info("Echo sending [#\(self.echoCounter)] len=\(text.count) preview=\(text.prefix(80), privacy: .public)")
        sendInteraction("conversation.echo", properties: [
            "modality": "text",
            "text": text,
            "inference_id": "echo_\(echoCounter)",
            "done": "true"
        ])

        // Collision recovery — if after 2s the echo has never actually
        // started speaking AND we saw LLM tokens streaming in, Tavus's
        // rogue LLM generation collided with our echo in the TTS pipeline.
        // Fire one recovery: interrupt + re-queue the same text. Fixes the
        // "avatar froze after patient answered / said a word twice" pattern.
        echoCollisionRecoveryTask?.cancel()
        let expectedEcho = echoCounter
        let recoveredText = text
        echoCollisionRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.runEchoCollisionRecoveryIfNeeded(expectedEcho: expectedEcho, text: recoveredText)
            }
        }
    }

    @MainActor
    private func runEchoCollisionRecoveryIfNeeded(expectedEcho: Int, text: String) {
        // Echo already moved on — nothing to do.
        guard echoInFlight, echoCounter == expectedEcho else { return }
        // Replica actually started speaking — this echo is healthy.
        guard inFlightEchoSpeakingCycles == 0 else { return }
        // No tokens streamed in — likely just a slow network / TTS cold
        // start, not a collision. Let the watchdog handle it if it stays stuck.
        guard inFlightEchoTokensSinceSent > 0 else { return }
        // Never fire twice on the same echo.
        guard !echoCollisionRecoveryFired else { return }
        echoCollisionRecoveryFired = true

        log.warning("⚠️ Echo#\(expectedEcho) collided with LLM stream (no replica.started_speaking after 2s, tokens=\(self.inFlightEchoTokensSinceSent)) — firing recovery")

        // Release the stuck slot and drain the LLM.
        releaseEchoSlot()
        log.info("Auto-interrupt: fired (reason=timeout-driven, source=echo-collision, echo#\(expectedEcho))")
        sendInteraction("conversation.interrupt")
        sendContextUpdate("RULES: Stay completely silent. Do NOT respond, acknowledge, or generate any speech. Only speak when given an echo command.")

        // Re-queue the same text so downstream continuation flows
        // (QAPhaseView speakQuestion, WordRegistration echo chain, etc.)
        // still resolve naturally via the next replica.stopped_speaking.
        echoTextQueue.insert(text, at: 0)
        // Wait 900ms before re-sending. At 400ms the rogue LLM's
        // partial TTS could still be bleeding into the audio mix,
        // producing a garbled blip right before the real echo starts.
        // 900ms gives Tavus enough time to fully drain the interrupted
        // LLM stream before we send the new echo.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.pumpEchoQueue()
        }
    }

    private func releaseEchoSlot() {
        guard echoInFlight else { return }
        echoWatchdogTask?.cancel()
        echoWatchdogTask = nil
        echoCollisionRecoveryTask?.cancel()
        echoCollisionRecoveryTask = nil
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

    // MARK: - Phase Scoping (speculative_inference toggle)

    /// Update the current assessment phase. If `speculative_inference` would
    /// flip, emit a `conversation.overwrite_llm_context` to the LLM layer so
    /// prefill behavior matches phase semantics.
    ///
    /// Scripted-echo subtest phases MUST have speculative_inference off — the
    /// LLM is not supposed to generate free-form output during those phases,
    /// and any prefill prediction would waste compute on content that gets
    /// overridden by the echo queue (with a small risk of leaking unscripted
    /// audio into the subtest stream).
    func setPhase(_ phase: AssessmentPhaseType) {
        guard phase != currentPhase else { return }
        let priorPhase = currentPhase
        currentPhase = phase
        // Phase-transition signpost so Instruments can overlay phase boundaries
        // on top of echo/mic/turn-state spans. `emitEvent` is a point-in-time
        // marker; echo/turn-state use intervals separately.
        signposter.emitEvent(
            "phase.transition",
            "\(priorPhase.rawValue) -> \(phase.rawValue)"
        )
        log.info("Phase transition: \(priorPhase.rawValue, privacy: .public) -> \(phase.rawValue, privacy: .public) (scripted=\(phase.isScoredSubtest))")
        NotificationCenter.default.post(
            name: .assessmentPhaseChanged,
            object: nil,
            userInfo: ["phase": phase.rawValue]
        )

        let wantSpec = phase.allowsSpeculativeInference
        guard wantSpec != lastSpeculativeSetting else { return }
        lastSpeculativeSetting = wantSpec

        log.info("Phase config: speculative_inference=\(wantSpec) (phase=\(phase.rawValue, privacy: .public))")

        // Push the LLM-layer toggle via overwrite_llm_context. Tavus's LLM
        // layer reads speculative_inference from the persona at session
        // start, but mid-session updates are delivered via this interaction.
        sendInteraction("conversation.overwrite_llm_context", properties: [
            "llm": ["speculative_inference": wantSpec]
        ])
        lastOverwriteContextAt = Date()
    }

    // MARK: - Session Abandonment Watchdog

    /// Arm the silence watchdog. Call this when the patient-facing phase
    /// enters a listening window. The watchdog fires a gentle re-prompt at
    /// 90s and hard-ends the session at 150s total silence.
    ///
    /// Calls to `beginSilenceWatch()` are idempotent — calling while already
    /// armed re-starts the clock from zero (useful when a new phase begins).
    func beginSilenceWatch() {
        // Voice mode (Task 6): this manager still observes the notification
        // seam even when no call exists (observers register in init, and
        // ContentView creates it unconditionally). Without a call it must
        // never arm — its fireAbandonment would post a competing
        // .sessionAbandoned + leave() against VoiceGuideService's watchdog.
        // Mirrors the existing guard in fireReengagementPrompt; inert in
        // avatar mode, where phases only arm after the room is joined.
        guard callState == .joined else { return }
        cancelSilenceWatch()
        silenceStartedAt = Date()
        reengagementPromptSent = false

        reengagementTask = Task { [weak self] in
            let nanos = UInt64((self?.reengagementAfter ?? 90.0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.fireReengagementPrompt() }
        }

        abandonmentTask = Task { [weak self] in
            let nanos = UInt64((self?.abandonmentAfter ?? 150.0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.fireAbandonment() }
        }
    }

    /// Disarm the silence watchdog. Call when the patient speaks or when the
    /// phase view transitions out of a listening window.
    func cancelSilenceWatch() {
        silenceStartedAt = nil
        reengagementTask?.cancel()
        reengagementTask = nil
        abandonmentTask?.cancel()
        abandonmentTask = nil
        reengagementPromptSent = false
    }

    private func fireReengagementPrompt() {
        guard silenceStartedAt != nil, !reengagementPromptSent else { return }
        guard callState == .joined else { return }
        reengagementPromptSent = true
        log.warning("Silence watchdog: 90s elapsed — sending re-engagement prompt")
        // Send directly through the echo queue. This uses conversation.echo so
        // the avatar speaks exact wording — no LLM ad-lib.
        sendEcho("Are you still there? Take your time.")
    }

    private func fireAbandonment() {
        guard let started = silenceStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        log.warning("Silence watchdog: \(elapsed, privacy: .public)s elapsed — ending session as abandoned")
        cancelSilenceWatch()
        shutdownReason = .abandonedSilence
        NotificationCenter.default.post(
            name: .sessionAbandoned,
            object: nil,
            userInfo: [
                "reason": SessionShutdownReason.abandonedSilence.rawValue,
                "silenceDuration": elapsed
            ]
        )
        // Leave the Daily room + let the app's shutdown flow handle partial
        // scoring. We intentionally DO NOT end the Tavus conversation here
        // — TavusService.endConversation is the authoritative teardown.
        leave()
    }

    // MARK: - System Shutdown

    /// Map a Tavus `system.shutdown` event to our internal reason enum and
    /// broadcast. Phase-view state machine + the report flow key off this.
    private func handleSystemShutdown(reason rawReason: String?) {
        let reason: SessionShutdownReason
        switch rawReason {
        case "participant_left":  reason = .participantLeft
        case "timeout":           reason = .timeout
        case "network_error":     reason = .networkError
        case "completed":         reason = .completed
        case let other?:
            log.warning("system.shutdown: unknown reason '\(other, privacy: .public)'")
            reason = .unknown
        case nil:
            reason = .unknown
        }

        log.info("system.shutdown: reason=\(reason.rawValue, privacy: .public) partial=\(reason.isPartial)")
        shutdownReason = reason
        cancelSilenceWatch()
        NotificationCenter.default.post(
            name: .sessionAbandoned,
            object: nil,
            userInfo: ["reason": reason.rawValue]
        )
    }

    // MARK: - Event Ordering (seq / turn_idx)

    /// Parse `seq` + `turn_idx` from a Tavus event payload and log any
    /// out-of-order delivery. Advance currentTurnIdx when it changes and
    /// broadcast to phase views.
    private func processEventOrdering(_ json: [String: Any], eventType: String) {
        // Both can arrive under the top level or nested in "properties".
        let seq = (json["seq"] as? Int)
            ?? ((json["properties"] as? [String: Any])?["seq"] as? Int)
        let turnIdx = (json["turn_idx"] as? Int)
            ?? ((json["properties"] as? [String: Any])?["turn_idx"] as? Int)

        if let s = seq {
            if s <= lastObservedSeq {
                log.warning("Out-of-order event: seq=\(s) <= last=\(self.lastObservedSeq) (\(eventType, privacy: .public))")
            } else {
                lastObservedSeq = s
            }
        }

        if let t = turnIdx, t != currentTurnIdx {
            currentTurnIdx = t
            NotificationCenter.default.post(
                name: .avatarTurnAdvanced,
                object: nil,
                userInfo: ["turnIdx": t]
            )
        }
    }

    // MARK: - Interrupt

    private func sendInterrupt() {
        echoTextQueue.removeAll()
        echoInFlight = false
        echoWatchdogTask?.cancel()
        echoWatchdogTask = nil
        log.info("Auto-interrupt: fired (reason=system-driven, source=explicit-request) — cleared echo queue and released echo slot")
        sendInteraction("conversation.interrupt")
    }

    // MARK: - Mic Control

    private func setMicMuted(_ muted: Bool) {
        if let client = callClient {
            setMicrophoneInputEnabledOffMain(client: client, enabled: !muted)
        }
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
        // Compute utterance duration for logging only.
        let startedAt = userStartedSpeakingAt
        userStartedSpeakingAt = nil
        let utteranceDuration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        log.info("Turn-state: userSpeaking -> processingUser [duration=\(String(format: "%.2f", utteranceDuration))s phase=\(self.currentPhase.rawValue, privacy: .public)]")

        // DEMO MODE: auto-interrupt / context-clobber disabled globally.
        // The original drain existed to suppress speculative LLM tokens that
        // raced the next echo, but in practice it was also clobbering
        // legitimate patient responses during recall / orientation. With the
        // persona guardrails ("stay silent between echo commands") the
        // speculative leak is bounded, and dropping the interrupt entirely
        // guarantees user responses are never truncated.
        log.info("Auto-interrupt: DISABLED (demo mode) — no interrupt or overwrite_llm_context will fire on user.stopped_speaking")
    }

    private func handleReplicaStartedSpeaking() {
        // Replica is actually speaking — no collision, cancel any
        // pending recovery check for this echo.
        echoCollisionRecoveryTask?.cancel()
        echoCollisionRecoveryTask = nil
        // A real echo is firing — the queued-follow-up safety-net is no
        // longer needed. `handleReplicaStoppedSpeaking` will re-arm it if
        // another chained echo is queued after this one.
        cancelMicUnmuteSafety()
        if echoInFlight || !echoTextQueue.isEmpty {
            inFlightEchoSpeakingCycles += 1
            let cycle = inFlightEchoSpeakingCycles
            let elapsed = inFlightEchoStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            // Expected echo — mute mic during avatar speech
            if let client = callClient {
                setMicrophoneInputEnabledOffMain(client: client, enabled: false)
            }
            log.info("Mic muted (avatar speaking) [echo#\(self.echoCounter) cycle=\(cycle) +\(String(format: "%.2f", elapsed))s tokensSinceSend=\(self.inFlightEchoTokensSinceSent)]")
            if cycle > 1 {
                log.warning("⚠️ Tavus emitted multiple started_speaking for single echo (cycle=\(cycle)) — possible mic re-cycling / audio glitch source")
            }
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
        let elapsed = inFlightEchoStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let cycles = inFlightEchoSpeakingCycles
        let echoNum = echoCounter
        let textPreview = inFlightEchoText.prefix(60)
        log.info("Turn-state: avatarSpeaking -> awaitingUser [echo#\(echoNum) cycles=\(cycles) elapsed=\(String(format: "%.2f", elapsed))s preview=\(textPreview, privacy: .public)]")

        releaseEchoSlot()

        // Reset diagnostics now that the echo is fully resolved.
        inFlightEchoStartedAt = nil
        inFlightEchoText = ""
        inFlightEchoSpeakingCycles = 0
        inFlightEchoTokensSinceSent = 0

        // DEMO MODE: force unmute on every replica stop, regardless of
        // queue state. The prior queue-gated unmute was leaving the mic
        // muted whenever a chained echo was queued — which during recall
        // prompts meant the patient's response was dropped. If a chained
        // echo actually fires next, `handleReplicaStartedSpeaking` will
        // mute again for its duration.
        if let client = callClient {
            setMicrophoneInputEnabledOffMain(client: client, enabled: true)
        }
        log.info("Mic FORCE-unmuted on replica stop (queue=\(self.echoTextQueue.count) inFlight=\(self.echoInFlight)) — turn-state=awaitingUser")
        cancelMicUnmuteSafety()
    }

    /// Arm the safety-unmute watchdog. Idempotent — cancels any prior task.
    private func armMicUnmuteSafety() {
        cancelMicUnmuteSafety()
        let window = micUnmuteSafetyWindow
        micUnmuteSafetyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(window))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run { self.fireMicUnmuteSafetyIfNeeded() }
        }
    }

    private func cancelMicUnmuteSafety() {
        micUnmuteSafetyTask?.cancel()
        micUnmuteSafetyTask = nil
    }

    @MainActor
    private func fireMicUnmuteSafetyIfNeeded() {
        // If a new echo is actively in flight, the normal flow will mute/unmute
        // naturally. Leave it alone.
        if echoInFlight || !echoTextQueue.isEmpty {
            log.debug("Mic safety-unmute skipped (queue=\(self.echoTextQueue.count) inFlight=\(self.echoInFlight))")
            return
        }
        // Only force-unmute if the mic is currently muted from our side.
        if lastMicEnabledDispatched == false {
            if let client = callClient {
                setMicrophoneInputEnabledOffMain(client: client, enabled: true)
            }
            log.warning("Mic force-unmuted by safety-net — queue drained without normal unmute path")
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
        beginSilenceObserver = NotificationCenter.default.addObserver(
            forName: .tavusBeginSilenceWatchRequest, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginSilenceWatch() }
        }
        cancelSilenceObserver = NotificationCenter.default.addObserver(
            forName: .tavusCancelSilenceWatchRequest, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelSilenceWatch() }
        }
        phaseTypeObserver = NotificationCenter.default.addObserver(
            forName: .tavusPhaseTypeRequest, object: nil, queue: .main
        ) { [weak self] notification in
            guard
                let raw = notification.userInfo?["phase"] as? String,
                let phase = AssessmentPhaseType(rawValue: raw)
            else { return }
            MainActor.assumeIsolated { self?.setPhase(phase) }
        }
    }

    private func removeNotificationObservers() {
        [contextObserver, echoObserver, respondObserver, muteObserver, interruptObserver,
         beginSilenceObserver, cancelSilenceObserver, phaseTypeObserver]
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

            // seq + turn_idx observability for every event.
            self.processEventOrdering(json, eventType: eventType)

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
                // Patient is vocalizing — cancel silence watch immediately
                // and stamp the start time so handleUserStoppedSpeaking can
                // compute utterance duration for the min-duration gate.
                self.patientIsSpeaking = true
                self.userStartedSpeakingAt = Date()
                self.cancelSilenceWatch()
                // Patient is speaking: the mic-unmute safety net is no
                // longer needed (we want the mic open, and it already is).
                self.cancelMicUnmuteSafety()
                log.info("Turn-state: awaitingUser -> userSpeaking")
                NotificationCenter.default.post(name: .patientStartedSpeaking, object: nil)

            case "conversation.user.stopped_speaking":
                self.patientIsSpeaking = false
                NotificationCenter.default.post(name: .patientDoneSpeaking, object: nil)
                self.handleUserStoppedSpeaking()

            case "system.replica_joined":
                log.info("Replica joined")

            case "system.replica_present":
                break // Heartbeat — ignore

            case "system.shutdown":
                let reason = (json["properties"] as? [String: Any])?["reason"] as? String
                    ?? json["reason"] as? String
                self.handleSystemShutdown(reason: reason)

            case "conversation.utterance":
                log.debug("Utterance event received")

            case "conversation.utterance.streaming":
                // High-frequency LLM token event. We don't act on it, but we
                // count tokens that arrive *during* an in-flight echo — those
                // indicate the LLM is generating its own response that will
                // collide with our SSML in the TTS pipeline (Fix-3 territory).
                if self.echoInFlight {
                    self.inFlightEchoTokensSinceSent += 1
                    if self.inFlightEchoTokensSinceSent == 1 {
                        log.warning("⚠️ LLM token arrived during in-flight echo#\(self.echoCounter) — TTS collision risk")
                    }
                }

            default:
                log.debug("Unhandled event: \(eventType, privacy: .public)")
            }
        }
    }
}
