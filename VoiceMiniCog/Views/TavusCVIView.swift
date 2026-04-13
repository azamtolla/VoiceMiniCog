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
}

// MARK: - CLINICAL-UI
// This view displays the AI avatar for voice-guided cognitive assessment.
// No PHI is rendered in the WebView — only the avatar video stream.

struct TavusCVIView: UIViewRepresentable {
    let conversationURL: String
    var onAvatarEvent: ((TavusAvatarEvent) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // Allow inline media playback (required for WebRTC video)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true

        // Register Swift message handler for JS → Swift bridge
        let contentController = config.userContentController
        contentController.add(context.coordinator, name: "tavusBridge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Store reference for sending JS commands later
        context.coordinator.webView = webView
        context.coordinator.conversationURL = conversationURL
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
        // No-op: conversation URL doesn't change during a session
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        let ptr = String(format: "%p", unsafeBitCast(webView, to: Int.self))
        print("[TavusCVI] dismantleUIView — WKWebView \(ptr) DESTROYED")
        cviLog.info("dismantleUIView — WKWebView \(ptr, privacy: .public) DESTROYED")
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var webView: WKWebView?
        var conversationURL: String?
        var onAvatarEvent: ((TavusAvatarEvent) -> Void)?
        private var hasJoined = false
        private var contextObserver: NSObjectProtocol?
        private var echoObserver: NSObjectProtocol?
        private var muteObserver: NSObjectProtocol?

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
            let ptr = String(format: "%p", unsafeBitCast(webView, to: Int.self))
            guard !hasJoined, let url = conversationURL else {
                print("[TavusCVI] didFinish — webView \(ptr), already joined or no URL")
                cviLog.info("didFinish — webView \(ptr, privacy: .public), already joined or no URL")
                return
            }
            hasJoined = true
            print("[TavusCVI] didFinish — webView \(ptr), joining room")
            cviLog.info("didFinish — webView \(ptr, privacy: .public), joining room")

            // joinRoom is async in the bridge JS — use callAsyncJavaScript
            // with parameterized argument to avoid URL injection.
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "await joinRoom(url);",
                        arguments: ["url": url],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    cviLog.error("joinRoom failed: \(error.localizedDescription, privacy: .public)")
                }
            }
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
                print("[TavusCVI] Left Daily room")
                cviLog.info("Left Daily room")
                onAvatarEvent?(.left)

            case "error":
                let msg = json["message"] as? String ?? "Unknown"
                print("[TavusCVI] Bridge error: \(msg)")
                cviLog.error("Bridge error: \(msg, privacy: .public)")
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
            guard let webView else { return }
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "sendContextUpdate(text);",
                        arguments: ["text": context],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    cviLog.error("Context update failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        /// Make the avatar speak exact text (bypasses LLM — for clinical prompts)
        func sendEcho(_ text: String) {
            guard let webView else { return }
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "sendEcho(text);",
                        arguments: ["text": text],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    cviLog.error("Echo failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        /// Interrupt the avatar (stop speaking immediately)
        func sendInterrupt() {
            guard let webView else { return }
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "sendInterrupt();",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    cviLog.error("Interrupt failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        /// Mute or unmute the patient's microphone via the Daily JS bridge
        func setMicMuted(_ muted: Bool) {
            guard let webView else { return }
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "setMicMuted(muted);",
                        arguments: ["muted": muted],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    cviLog.error("setMicMuted failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        /// Adjust turn-taking sensitivity
        func setSensitivity(pause: String, interrupt: String) {
            guard let webView else { return }
            Task { @MainActor in
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "setSensitivity(p, i);",
                        arguments: ["p": pause, "i": interrupt],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    cviLog.error("setSensitivity failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // MARK: Navigation Error Handling

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            let ptr = String(format: "%p", unsafeBitCast(webView, to: Int.self))
            cviLog.error("Navigation failed — webView \(ptr, privacy: .public): \(error.localizedDescription, privacy: .public)")
            hasJoined = false  // allow rejoin on next successful navigation
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            let ptr = String(format: "%p", unsafeBitCast(webView, to: Int.self))
            cviLog.error("Load failed — webView \(ptr, privacy: .public): \(error.localizedDescription, privacy: .public)")
            hasJoined = false  // allow rejoin on next successful navigation
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
    avatarSetContext(context + " " + LeftPaneSpeechCopy.examinerNeverCorrectPatient)
}

/// Mute or unmute the patient's microphone in the active Daily call.
func avatarSetMicMuted(_ muted: Bool) {
    NotificationCenter.default.post(
        name: .tavusMicMuteRequest,
        object: nil,
        userInfo: ["muted": muted]
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
