//
//  TavusCVIView.swift
//  VoiceMiniCog
//
//  Embeds a Tavus CVI conversation via a custom Daily JS bridge page.
//  Provides full bidirectional communication between Swift and the
//  Tavus avatar through Daily's sendAppMessage API.
//
//  Swift → JS: sendContextUpdate, sendEcho, sendInterrupt
//  JS → Swift: WKScriptMessageHandler for avatar events
//

import SwiftUI
import WebKit
import os

private let cviLog = Logger(subsystem: "com.mercycog.VoiceMiniCog", category: "TavusCVI")

extension Notification.Name {
    static let tavusContextUpdate = Notification.Name("tavusContextUpdate")
    static let tavusEchoRequest = Notification.Name("tavusEchoRequest")
    /// Fired when the avatar starts speaking (replica started)
    static let avatarStartedSpeaking = Notification.Name("avatarStartedSpeaking")
    /// Fired when the avatar finishes speaking (replica stopped)
    static let avatarDoneSpeaking = Notification.Name("avatarDoneSpeaking")
    /// Fired when the patient finishes speaking (user stopped)
    static let patientDoneSpeaking = Notification.Name("patientDoneSpeaking")
    /// Fired when the patient starts speaking (user started) — used to ignore orphan `stopped` events
    static let patientStartedSpeaking = Notification.Name("patientStartedSpeaking")
    /// Daily room joined — WebView bridge can now deliver echos; welcome may replay if the first echo was missed.
    static let tavusDailyRoomJoined = Notification.Name("tavusDailyRoomJoined")
    /// Mute/unmute the patient's microphone in the Daily call
    static let tavusMicMuteRequest = Notification.Name("tavusMicMuteRequest")
    /// Request to interrupt avatar speech and clear the echo queue
    static let tavusInterruptRequest = Notification.Name("tavusInterruptRequest")
    static let tavusRespondRequest = Notification.Name("tavusRespondRequest")
    /// Fired when the Daily WebRTC connection drops mid-session (left-meeting or fatal error)
    static let tavusConnectionLost = Notification.Name("tavusConnectionLost")
}

// MARK: - CLINICAL-UI
// This view displays the AI avatar for voice-guided cognitive assessment.
// No PHI is rendered in the WebView — only the avatar video stream.

struct TavusCVIView: UIViewRepresentable {
    let conversationURL: String
    /// When true with a pre-warmed session on Home, load the bridge but do **not** call `joinRoom`
    /// until this becomes false (assessment active). Prevents Tavus from speaking unprompted
    /// (e.g. "hello") while `isActive` is still false.
    var deferDailyRoomJoinUntilAssessmentActive: Bool = false
    var onAvatarEvent: ((TavusAvatarEvent) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Allow inline media playback (required for WebRTC video)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        // Allow WKWebView's WebContent process to access hardware decoders
        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = preferences

        // Prevent iOS 15.4+ from upgrading Daily's WebRTC signaling
        // connections, which can break the replica join handshake.
        if #available(iOS 15.4, *) {
            config.upgradeKnownHostsToHTTPS = false
        }

        // Register Swift message handler for JS → Swift bridge.
        // Fix #5: use WeakScriptHandler to break the retain cycle:
        // WKWebView → config → userContentController → handler → coordinator → webView
        let contentController = config.userContentController
        let weakHandler = WeakScriptHandler()
        weakHandler.delegate = context.coordinator
        contentController.add(weakHandler, name: "tavusBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        // Daily.co's browser-compat check rejects WKWebView's default UA;
        // declaring Safari makes Daily treat this as a supported iOS browser.
        webView.customUserAgent = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Store reference for sending JS commands later
        context.coordinator.webView = webView
        context.coordinator.conversationURL = conversationURL
        context.coordinator.deferDailyRoomJoinUntilAssessmentActive = deferDailyRoomJoinUntilAssessmentActive
        context.coordinator.onAvatarEvent = onAvatarEvent

        let ptr = String(format: "%p", unsafeBitCast(webView, to: Int.self))
        print("[TavusCVI] makeUIView — WKWebView \(ptr) created")
        cviLog.info("makeUIView — WKWebView \(ptr, privacy: .public) created")

        // Load the custom bridge HTML — restrict read access to the file itself
        // to prevent bridge JS from reading other files in Resources/.
        if let bridgePath = Bundle.main.path(forResource: "TavusBridge", ofType: "html") {
            let bridgeURL = URL(fileURLWithPath: bridgePath)
            webView.loadFileURL(bridgeURL, allowingReadAccessTo: bridgeURL)
            cviLog.info("Loading bridge HTML (webView \(ptr, privacy: .public))")
        } else {
            cviLog.error("TavusBridge.html not found in bundle")
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.conversationURL = conversationURL
        coordinator.webView = webView
        coordinator.deferDailyRoomJoinUntilAssessmentActive = deferDailyRoomJoinUntilAssessmentActive
        coordinator.onAvatarEvent = onAvatarEvent
        // Fix #4: single join dispatch — attemptJoinIfPossible handles all cases
        // including the deferred→active transition.
        coordinator.attemptJoinIfPossible()
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Fix #6: remove script message handler to break any residual strong refs
        // and prevent JS messages from firing on a stale coordinator.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tavusBridge")
        coordinator.webView = nil
        cviLog.info("dismantleUIView — WKWebView DESTROYED, script handler removed")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var conversationURL: String?
        var onAvatarEvent: ((TavusAvatarEvent) -> Void)?
        /// When true, `didFinish` loads bridge JS only — Daily `joinRoom` waits until assessment is active.
        var deferDailyRoomJoinUntilAssessmentActive = false
        private var hasJoined = false
        /// True after first successful `didFinish` for the bridge document — `sendEcho` / `sendContextUpdate` exist in JS.
        private var isBridgeDocumentReady = false
        /// Ops received before the bridge script is executable (race with Welcome `onAppear`).
        private var pendingUntilDocumentReady: [PendingBridgeOp] = []
        /// Serializes WK `callAsyncJavaScript` so `overwrite_context` cannot overlap `sendEcho` (H2).
        private var bridgeExecutionChain: Task<Void, Never>?
        private var contextObserver: NSObjectProtocol?
        private var echoObserver: NSObjectProtocol?
        private var muteObserver: NSObjectProtocol?
        private var interruptObserver: NSObjectProtocol?
        private var respondObserver: NSObjectProtocol?

        private enum PendingBridgeOp {
            case context(String)
            case echo(String)
            case interrupt
            case micMuted(Bool)
            case sensitivity(pause: String, interrupt: String)
            case respond(String)
        }

        override init() {
            super.init()
            // Listen for context update notifications from AvatarAssessmentCanvas
            contextObserver = NotificationCenter.default.addObserver(
                forName: .tavusContextUpdate,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let context = notification.userInfo?["context"] as? String {
                    self?.sendContextUpdate(context)
                }
            }
            // Listen for explicit avatar speech text from the left content pane.
            echoObserver = NotificationCenter.default.addObserver(
                forName: .tavusEchoRequest,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let text = notification.userInfo?["text"] as? String, !text.isEmpty {
                    self?.sendEcho(text)
                }
            }
            // Listen for mic mute/unmute requests
            muteObserver = NotificationCenter.default.addObserver(
                forName: .tavusMicMuteRequest,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let muted = notification.userInfo?["muted"] as? Bool {
                    self?.setMicMuted(muted)
                }
            }
            interruptObserver = NotificationCenter.default.addObserver(
                forName: .tavusInterruptRequest,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.sendInterrupt()
            }
            respondObserver = NotificationCenter.default.addObserver(
                forName: .tavusRespondRequest,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let text = notification.userInfo?["text"] as? String, !text.isEmpty {
                    self?.sendRespond(text)
                }
            }
        }

        deinit {
            if let observer = contextObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = echoObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = muteObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = interruptObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = respondObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            bridgeExecutionChain?.cancel()
            bridgeExecutionChain = nil
        }

        /// Run bridge JS strictly one-at-a-time on the main actor.
        private func enqueueBridgeJS(
            _ label: String,
            _ body: @escaping @MainActor () async throws -> Void
        ) {
            let previous = bridgeExecutionChain
            bridgeExecutionChain = Task { @MainActor [weak self] in
                if let previous {
                    await previous.value
                }
                guard self != nil else { return }
                do {
                    try await body()
                } catch {
                    cviLog.error("\(label) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        private func enqueueOrDefer(_ op: PendingBridgeOp) {
            if !isBridgeDocumentReady {
                pendingUntilDocumentReady.append(op)
                return
            }
            switch op {
            case .context(let s): runSendContextUpdate(s)
            case .echo(let s): runSendEcho(s)
            case .interrupt: runSendInterrupt()
            case .micMuted(let m): runSetMicMuted(m)
            case .sensitivity(let p, let i): runSetSensitivity(pause: p, interrupt: i)
            case .respond(let s): runSendRespond(s)
            }
        }

        /// Run deferred ops in one serialized `callAsyncJavaScript` chain (no nested `enqueueBridgeJS` per op).
        private func performPendingOpsInlineSequential() async throws {
            guard let webView else { return }
            let batch = pendingUntilDocumentReady
            pendingUntilDocumentReady.removeAll()
            guard !batch.isEmpty else { return }
            for op in batch {
                switch op {
                case .context(let text):
                    _ = try await webView.callAsyncJavaScript(
                        "sendContextUpdate(text);",
                        arguments: ["text": text],
                        in: nil,
                        contentWorld: .page
                    )
                case .echo(let text):
                    _ = try await webView.callAsyncJavaScript(
                        "sendEcho(text);",
                        arguments: ["text": text],
                        in: nil,
                        contentWorld: .page
                    )
                case .interrupt:
                    _ = try await webView.callAsyncJavaScript(
                        "sendInterrupt();",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                case .micMuted(let muted):
                    _ = try await webView.callAsyncJavaScript(
                        "setMicMuted(muted);",
                        arguments: ["muted": muted],
                        in: nil,
                        contentWorld: .page
                    )
                case .sensitivity(let pause, let interrupt):
                    _ = try await webView.callAsyncJavaScript(
                        "setSensitivity(p, i);",
                        arguments: ["p": pause, "i": interrupt],
                        in: nil,
                        contentWorld: .page
                    )
                case .respond(let text):
                    _ = try await webView.callAsyncJavaScript(
                        "sendRespond(text);",
                        arguments: ["text": text],
                        in: nil,
                        contentWorld: .page
                    )
                }
            }
        }

        /// Consolidated join entry point — handles both immediate and deferred-from-Home paths.
        /// Fix #1: hasJoined set inside closure after guards pass, not before.
        /// Fix #2: performPendingOps only runs after successful join.
        /// Fix #4: single method replaces attemptJoinIfPossible + beginDailyJoinIfReady.
        func attemptJoinIfPossible() {
            guard !deferDailyRoomJoinUntilAssessmentActive else { return }
            guard isBridgeDocumentReady, !hasJoined else { return }
            guard webView != nil, let url = conversationURL else { return }
            hasJoined = true
            cviLog.info("attemptJoinIfPossible — joining room")
            enqueueBridgeJS("unlockAudio+joinRoomAndFlush") { [weak self] in
                guard let self, let webView = self.webView else { return }
                do {
                    // Step 1: Unlock Web Audio API (iOS suspends AudioContexts by default)
                    _ = try await webView.callAsyncJavaScript(
                        "await unlockAudio();",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                    // Step 2: Join the Daily room
                    _ = try await webView.callAsyncJavaScript(
                        "await joinRoom(url);",
                        arguments: ["url": url],
                        in: nil,
                        contentWorld: .page
                    )
                    // Fix #2: only flush pending ops after a successful join.
                    try await self.performPendingOpsInlineSequential()
                } catch {
                    cviLog.error("joinRoom failed: \(error.localizedDescription, privacy: .public)")
                    // Join failed — allow retry on next attemptJoinIfPossible call.
                    self.hasJoined = false
                }
            }
        }

        // MARK: Camera/Mic Permission Grant

        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            // Allowlist: local bridge file (file://) + Tavus and Daily domains.
            // Any other origin is denied — prevents remote frames or future
            // code changes from silently gaining mic/camera access to PHI.
            let host = origin.host.lowercased()
            let allowed = origin.protocol == "file"
                || host.hasSuffix("tavus.io")
                || host.hasSuffix("daily.co")
                || host.hasSuffix("daily.com")
            if allowed {
                decisionHandler(.grant)
            } else {
                cviLog.warning("Denied media capture from non-allowlisted origin: \(host, privacy: .public)")
                decisionHandler(.deny)
            }
        }

        // MARK: Bridge Page Loaded → Join Room

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            let ptr = String(format: "%p", unsafeBitCast(webView, to: Int.self))
            cviLog.info("didCommit — webView \(ptr, privacy: .public)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            self.webView = webView
            if !isBridgeDocumentReady {
                isBridgeDocumentReady = true
            }
            cviLog.info("didFinish — bridge document ready")
            // Delegate to the single join path — it handles all cases
            // (already joined, no URL, deferred, ready to join).
            attemptJoinIfPossible()
        }

        // MARK: JS → Swift Message Handler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? String,
                  let data = body.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String
            else { return }

            switch type {
            case "log":
                let msg = json["message"] as? String ?? ""
                cviLog.debug("Bridge: \(msg, privacy: .private)")

            case "joined":
                print("[TavusCVI] Joined Daily room")
                cviLog.info("Joined Daily room")
                onAvatarEvent?(.joined)
                NotificationCenter.default.post(name: .tavusDailyRoomJoined, object: nil)

            case "left":
                cviLog.info("Left Daily room")
                onAvatarEvent?(.left)
                // Fix #14: only post connectionLost if the leave was unexpected
                // (hasJoined still true = we didn't intend to leave).
                // A clean session end calls leaveRoom() which sets hasJoined = false
                // before the left event arrives.
                if hasJoined {
                    hasJoined = false
                    NotificationCenter.default.post(name: .tavusConnectionLost, object: nil)
                }

            case "error":
                let msg = json["message"] as? String ?? "Unknown"
                // Daily `network-connection` with `event: connected` (signaling + SFU) is normal setup noise;
                // the bridge posts it as `type: error` for diagnostics — do not surface as a user-facing error.
                if msg.hasPrefix("network-connection:"), msg.contains("\"event\":\"connected\"") {
                    cviLog.debug("Bridge (network ok): \(msg, privacy: .public)")
                    return
                }
                print("[TavusCVI] Bridge error: \(msg)")
                cviLog.error("Bridge error: \(msg, privacy: .public)")
                if !msg.hasPrefix("nonfatal-error:") {
                    NotificationCenter.default.post(
                        name: .tavusConnectionLost,
                        object: nil,
                        userInfo: ["message": msg]
                    )
                }
                onAvatarEvent?(.error(msg))

            case "tavusEvent":
                if let event = json["event"] as? [String: Any],
                   let eventType = event["event_type"] as? String {
                    cviLog.debug("Tavus event: \(eventType, privacy: .public)")
                    switch eventType {
                    case "conversation.replica.started_speaking":
                        onAvatarEvent?(.replicaStartedSpeaking)
                        NotificationCenter.default.post(name: .avatarStartedSpeaking, object: nil)
                    case "conversation.replica.stopped_speaking":
                        onAvatarEvent?(.replicaStoppedSpeaking)
                        NotificationCenter.default.post(name: .avatarDoneSpeaking, object: nil)
                    case "conversation.user.started_speaking":
                        onAvatarEvent?(.userStartedSpeaking)
                        NotificationCenter.default.post(name: .patientStartedSpeaking, object: nil)
                    case "conversation.user.stopped_speaking":
                        onAvatarEvent?(.userStoppedSpeaking)
                        NotificationCenter.default.post(name: .patientDoneSpeaking, object: nil)
                    default:
                        break
                    }
                }

            default:
                break
            }
        }

        // MARK: Swift → JS Interaction Methods
        //
        // All methods use callAsyncJavaScript with parameterized arguments
        // to prevent JavaScript injection. Values are passed as native
        // arguments, never interpolated into JS strings.

        /// Update the avatar's conversation context (tells it what phase/state we're in)
        func sendContextUpdate(_ context: String) {
            enqueueOrDefer(.context(context))
        }

        /// Make the avatar speak exact text (bypasses LLM — for clinical prompts)
        func sendEcho(_ text: String) {
            enqueueOrDefer(.echo(text))
        }

        /// Make the avatar speak exact text via conversation.respond (bypasses LLM — faster than echo)
        func sendRespond(_ text: String) {
            enqueueOrDefer(.respond(text))
        }

        /// Interrupt the avatar (stop speaking immediately)
        func sendInterrupt() {
            enqueueOrDefer(.interrupt)
        }

        /// Mute or unmute the patient's microphone via the Daily JS bridge
        func setMicMuted(_ muted: Bool) {
            enqueueOrDefer(.micMuted(muted))
        }

        /// Adjust turn-taking sensitivity
        func setSensitivity(pause: String, interrupt: String) {
            enqueueOrDefer(.sensitivity(pause: pause, interrupt: interrupt))
        }

        private func runSendContextUpdate(_ context: String) {
            enqueueBridgeJS("Context update") { [weak self] in
                guard let webView = self?.webView else { return }
                _ = try await webView.callAsyncJavaScript(
                    "sendContextUpdate(text);",
                    arguments: ["text": context],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func runSendEcho(_ text: String) {
            enqueueBridgeJS("Echo") { [weak self] in
                guard let webView = self?.webView else { return }
                _ = try await webView.callAsyncJavaScript(
                    "sendEcho(text);",
                    arguments: ["text": text],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func runSendRespond(_ text: String) {
            enqueueBridgeJS("Respond") { [weak self] in
                guard let webView = self?.webView else { return }
                _ = try await webView.callAsyncJavaScript(
                    "sendRespond(text);",
                    arguments: ["text": text],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func runSendInterrupt() {
            enqueueBridgeJS("Interrupt") { [weak self] in
                guard let webView = self?.webView else { return }
                _ = try await webView.callAsyncJavaScript(
                    "sendInterrupt();",
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func runSetMicMuted(_ muted: Bool) {
            enqueueBridgeJS("setMicMuted") { [weak self] in
                guard let webView = self?.webView else { return }
                _ = try await webView.callAsyncJavaScript(
                    "setMicMuted(muted);",
                    arguments: ["muted": muted],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        private func runSetSensitivity(pause: String, interrupt: String) {
            enqueueBridgeJS("setSensitivity") { [weak self] in
                guard let webView = self?.webView else { return }
                _ = try await webView.callAsyncJavaScript(
                    "setSensitivity(p, i);",
                    arguments: ["p": pause, "i": interrupt],
                    in: nil,
                    contentWorld: .page
                )
            }
        }

        // MARK: Navigation Error Handling

        /// Fix #3 + #7: reset all bridge state on navigation failure so a reload
        /// starts from a clean slate. Without this, isBridgeDocumentReady stays
        /// true and stale pendingUntilDocumentReady ops replay on the new page.
        private func resetBridgeState() {
            hasJoined = false
            isBridgeDocumentReady = false
            pendingUntilDocumentReady.removeAll()
            bridgeExecutionChain?.cancel()
            bridgeExecutionChain = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            cviLog.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
            resetBridgeState()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            cviLog.error("Load failed: \(error.localizedDescription, privacy: .public)")
            resetBridgeState()
        }
    }
}

// MARK: - Avatar Speech Helper

/// Post a notification to make the Tavus avatar speak the given text via sendEcho().
/// Call this from any phase view when content appears on the left panel.
func avatarSpeak(_ text: String) {
    guard !text.isEmpty else { return }
    NotificationCenter.default.post(
        name: .tavusEchoRequest,
        object: nil,
        userInfo: ["text": text]
    )
}

/// Make the avatar speak exact text via conversation.respond (bypasses LLM — faster than echo).
/// Use for scripted assessment prompts where the text is predetermined.
func avatarRespond(_ text: String) {
    guard !text.isEmpty else { return }
    NotificationCenter.default.post(
        name: .tavusRespondRequest,
        object: nil,
        userInfo: ["text": text]
    )
}

/// Override the avatar's conversational context. This controls what the avatar's
/// LLM knows about the current state and how it should respond to patient speech.
/// Use this to prevent the avatar from advancing phases on its own.
func avatarSetContext(_ context: String) {
    guard !context.isEmpty else { return }
    NotificationCenter.default.post(
        name: .tavusContextUpdate,
        object: nil,
        userInfo: ["context": context]
    )
}

/// Set assessment context with examinerNeverCorrectPatient automatically appended.
/// Use this instead of `avatarSetContext` in all QMCI subtest phase views to
/// enforce the protocol constraint that the examiner never confirms or denies
/// patient responses. This eliminates the regression risk of forgetting to
/// append the rule at each individual call site.
func avatarSetAssessmentContext(_ context: String) {
    // Fix #13: guard against doubling if the caller's context already includes the rule.
    let rule = LeftPaneSpeechCopy.examinerNeverCorrectPatient
    if context.contains(rule) {
        avatarSetContext(context)
    } else {
        avatarSetContext(context + " " + rule)
    }
}

/// Mute or unmute the patient's microphone in the active Daily call.
func avatarSetMicMuted(_ muted: Bool) {
    NotificationCenter.default.post(
        name: .tavusMicMuteRequest,
        object: nil,
        userInfo: ["muted": muted]
    )
}

/// Interrupt the avatar — stops current speech and clears the echo queue.
/// Call this at the start of every phase onAppear to prevent stale echoes
/// from the previous phase overlapping with the new phase's first instruction.
func avatarInterrupt() {
    NotificationCenter.default.post(
        name: .tavusInterruptRequest,
        object: nil
    )
}

// MARK: - Avatar Events

enum TavusAvatarEvent {
    case joined
    case left
    case error(String)
    case replicaStartedSpeaking
    case replicaStoppedSpeaking
    case userStartedSpeaking
    case userStoppedSpeaking
}

// MARK: - Weak Script Handler (Fix #5)

/// Breaks the WKUserContentController → Coordinator retain cycle.
/// WKUserContentController holds a strong reference to its WKScriptMessageHandler;
/// without this proxy, Coordinator (and hence the WKWebView) would never deallocate.
private class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
