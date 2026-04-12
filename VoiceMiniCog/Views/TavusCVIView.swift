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

        // Load the custom bridge HTML
        if let bridgePath = Bundle.main.path(forResource: "TavusBridge", ofType: "html") {
            let bridgeURL = URL(fileURLWithPath: bridgePath)
            webView.loadFileURL(bridgeURL, allowingReadAccessTo: bridgeURL.deletingLastPathComponent())
            print("[TavusCVI] Loading bridge HTML")
        } else {
            print("[TavusCVI] ERROR: TavusBridge.html not found in bundle")
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // No-op: conversation URL doesn't change during a session
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
        }

        deinit {
            if let observer = contextObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = echoObserver {
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
            decisionHandler(.grant)
        }

        // MARK: Bridge Page Loaded → Join Room

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasJoined, let url = conversationURL else { return }
            hasJoined = true
            print("[TavusCVI] Bridge loaded, joining room: \(url)")

            let js = "joinRoom('\(url)');"
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    print("[TavusCVI] joinRoom error: \(error.localizedDescription)")
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
                print("[TavusBridge] \(msg)")

            case "joined":
                print("[TavusCVI] ✅ Joined Daily room")
                onAvatarEvent?(.joined)
                NotificationCenter.default.post(name: .tavusDailyRoomJoined, object: nil)

            case "left":
                print("[TavusCVI] Left Daily room")
                onAvatarEvent?(.left)

            case "error":
                let msg = json["message"] as? String ?? "Unknown"
                print("[TavusCVI] ❌ Error: \(msg)")
                onAvatarEvent?(.error(msg))

            case "tavusEvent":
                if let event = json["event"] as? [String: Any],
                   let eventType = event["event_type"] as? String {
                    print("[TavusCVI] Tavus event: \(eventType)")
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

        /// Update the avatar's conversation context (tells it what phase/state we're in)
        func sendContextUpdate(_ context: String) {
            let escaped = context
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = "sendContextUpdate('\(escaped)');"
            webView?.evaluateJavaScript(js) { _, error in
                if let error { print("[TavusCVI] Context update error: \(error.localizedDescription)") }
            }
        }

        /// Make the avatar speak exact text (bypasses LLM — for clinical prompts)
        func sendEcho(_ text: String) {
            let escaped = text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            let js = "sendEcho('\(escaped)');"
            webView?.evaluateJavaScript(js) { _, error in
                if let error { print("[TavusCVI] Echo error: \(error.localizedDescription)") }
            }
        }

        /// Interrupt the avatar (stop speaking immediately)
        func sendInterrupt() {
            webView?.evaluateJavaScript("sendInterrupt();", completionHandler: nil)
        }

        /// Adjust turn-taking sensitivity
        func setSensitivity(pause: String, interrupt: String) {
            let js = "setSensitivity('\(pause)', '\(interrupt)');"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        // MARK: Navigation Error Handling

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[TavusCVI] Navigation failed: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[TavusCVI] Load failed: \(error.localizedDescription)")
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
