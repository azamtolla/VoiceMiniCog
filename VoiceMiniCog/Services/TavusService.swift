//
//  TavusService.swift
//  VoiceMiniCog
//
//  Manages Tavus CVI conversation lifecycle.
//  Creates conversations via Tavus API, returns Daily room URL for WebRTC embedding.
//

import Foundation
import SwiftUI
import WebKit

// MARK: - CLINICAL
// This service manages avatar-guided assessment sessions.
// No PHI is stored locally — all audio is processed ephemerally by Tavus.

@Observable
final class TavusService {
    // MARK: - Configuration

    static let shared = TavusService()

    /// Tavus API key — loaded from UserDefaults (configured in Settings)
    var apiKey: String {
        UserDefaults.standard.string(forKey: "tavus_api_key") ?? "ad59dab220804a8f81f07e21e78b5ba6"
    }

    /// Default persona for clinical assessment
    var personaId: String {
        UserDefaults.standard.string(forKey: "tavus_persona_id")
            ?? "pc64945f7e08" // Clinical Neuropsychologist persona
    }

    /// Default replica
    var replicaId: String {
        UserDefaults.standard.string(forKey: "tavus_replica_id")
            ?? "rf4e9d9790f0" // Anna - Professional
    }

    // MARK: - State

    var isCreatingConversation = false
    var activeConversation: TavusConversationSession?
    var lastError: String?
    private var preWarmTask: Task<Void, Never>?

    // MARK: - WebView Pre-loading

    /// Pre-loaded WKWebView with bridge HTML loaded and (if ready) room joined.
    private(set) var preloadedWebView: WKWebView?
    /// The handler registered as WKScriptMessageHandler on the pre-loaded WebView.
    /// Stays alive even after the WebView is claimed, since WK retains it.
    private(set) var preloadHandler: TavusPreloadHandler?

    // MARK: - Pre-Warming

    /// Start creating a conversation AND loading the WebView in parallel.
    /// Call this when the Home screen appears.
    @MainActor
    func preWarm() {
        guard activeConversation == nil, !isCreatingConversation else { return }
        guard !apiKey.isEmpty else { return }

        // 1. Start loading the WebView + bridge HTML immediately (no URL needed yet)
        preloadWebView()

        // 2. Create the conversation in parallel
        preWarmTask = Task {
            do {
                _ = try await createConversation(
                    conversationName: "MercyCog Assessment \(Date().formatted(date: .abbreviated, time: .shortened))"
                )
                // Conversation ready — tell the preload handler to join the room
                await MainActor.run {
                    preloadHandler?.joinIfReady(
                        url: activeConversation?.conversation_url
                    )
                }
                print("[Tavus] Pre-warm: conversation ready, joining room")
            } catch {
                print("[Tavus] Pre-warm failed (will retry on Start): \(error.localizedDescription)")
            }
        }
    }

    /// Create and configure the WKWebView, load bridge HTML.
    @MainActor
    private func preloadWebView() {
        guard preloadedWebView == nil else { return }

        let handler = TavusPreloadHandler()
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(handler, name: "tavusBridge")

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = handler
        webView.uiDelegate = handler

        handler.webView = webView
        // When the bridge finishes loading and the conversation URL arrives later,
        // the handler will try to join automatically.
        handler.onConversationURLReady = { [weak self] in
            self?.activeConversation?.conversation_url
        }

        if let bridgePath = Bundle.main.path(forResource: "TavusBridge", ofType: "html") {
            let bridgeURL = URL(fileURLWithPath: bridgePath)
            webView.loadFileURL(bridgeURL, allowingReadAccessTo: bridgeURL.deletingLastPathComponent())
            print("[Tavus] Pre-load: loading bridge HTML")
        }

        self.preloadedWebView = webView
        self.preloadHandler = handler
    }

    /// Claim the pre-loaded WebView for display. Returns nil if nothing was pre-loaded.
    func claimPreloadedWebView() -> WKWebView? {
        let webView = preloadedWebView
        preloadedWebView = nil
        return webView
    }

    /// Cancel and clean up a pre-warmed conversation that was never used.
    func cancelPreWarm() {
        preWarmTask?.cancel()
        preWarmTask = nil
        preloadedWebView = nil
        preloadHandler = nil
        if let conversation = activeConversation {
            let cid = conversation.conversation_id
            activeConversation = nil
            Task { await endConversation(cid) }
        }
    }

    // MARK: - Conversation Lifecycle

    /// Creates a new Tavus conversation and returns the session with Daily room URL
    func createConversation(
        personaId: String? = nil,
        replicaId: String? = nil,
        conversationName: String? = nil
    ) async throws -> TavusConversationSession {
        let pid = personaId ?? self.personaId
        let rid = replicaId ?? self.replicaId

        guard !apiKey.isEmpty else {
            throw TavusError.missingAPIKey
        }

        await MainActor.run {
            isCreatingConversation = true
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isCreatingConversation = false
            }
        }

        // Build request body
        var body: [String: Any] = [
            "replica_id": rid,
            "persona_id": pid,
            // Clinical conversational flow: filter ambient noise, allow deliberate
            // interruptions, and give elderly patients time to respond.
            "layers": [
                "conversational_flow": [
                    "voice_isolation": "near",
                    "replica_interruptibility": "medium",
                    "turn_taking_patience": "high",
                    "turn_detection_model": "sparrow-1"
                ]
            ]
        ]
        if let name = conversationName {
            body["conversation_name"] = name
        }

        // Tavus API call
        let url = URL(string: "https://tavusapi.com/v2/conversations")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TavusError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TavusError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let session = try JSONDecoder().decode(TavusConversationSession.self, from: data)

        await MainActor.run {
            activeConversation = session
        }

        return session
    }

    /// Ends an active Tavus conversation
    func endConversation(_ conversationId: String? = nil) async {
        let cid = conversationId ?? activeConversation?.conversation_id
        guard let cid else { return }

        let url = URL(string: "https://tavusapi.com/v2/conversations/\(cid)/end")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try? await URLSession.shared.data(for: request)

        await MainActor.run {
            activeConversation = nil
        }
    }

    /// Checks if the API key is configured and valid
    func validateConfiguration() -> Bool {
        !apiKey.isEmpty
    }
}

// MARK: - WebView Preload Handler

/// Lightweight WK delegate that loads the bridge HTML, joins the Daily room,
/// and forwards JS→Swift messages. Stays registered as the WKScriptMessageHandler
/// for the lifetime of the WebView — messages are forwarded via `onAvatarEvent`.
final class TavusPreloadHandler: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private var bridgeLoaded = false
    private(set) var hasJoined = false

    /// Called to get the conversation URL (may not be available yet when bridge loads).
    var onConversationURLReady: (() -> String?)?

    /// Set by TavusCVIView.Coordinator after claiming to receive avatar events.
    var onAvatarEvent: ((TavusAvatarEvent) -> Void)?

    // MARK: Media Permission

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    // MARK: Bridge Loaded

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bridgeLoaded = true
        print("[TavusPreload] Bridge HTML loaded")
        // If conversation URL is already available, join now
        if let url = onConversationURLReady?() {
            joinRoom(url: url)
        }
    }

    /// Called by TavusService when the conversation URL becomes available,
    /// or when the bridge finishes loading (whichever comes second).
    func joinIfReady(url: String?) {
        guard bridgeLoaded, let url, !hasJoined else { return }
        joinRoom(url: url)
    }

    private func joinRoom(url: String) {
        guard !hasJoined else { return }
        hasJoined = true
        let js = "joinRoom('\(url)');"
        webView?.evaluateJavaScript(js) { _, error in
            if let error {
                print("[TavusPreload] joinRoom error: \(error.localizedDescription)")
            } else {
                print("[TavusPreload] joinRoom called — connecting to Daily room")
            }
        }
    }

    // MARK: JS → Swift Messages

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
            print("[TavusPreload] \(msg)")

        case "joined":
            print("[TavusPreload] Joined Daily room")
            onAvatarEvent?(.joined)

        case "left":
            onAvatarEvent?(.left)

        case "error":
            let msg = json["message"] as? String ?? "Unknown"
            print("[TavusPreload] Error: \(msg)")
            onAvatarEvent?(.error(msg))

        case "tavusEvent":
            if let event = json["event"] as? [String: Any],
               let eventType = event["event_type"] as? String {
                switch eventType {
                case "conversation.replica.started_speaking":
                    onAvatarEvent?(.replicaStartedSpeaking)
                case "conversation.replica.stopped_speaking":
                    onAvatarEvent?(.replicaStoppedSpeaking)
                case "conversation.user.started_speaking":
                    onAvatarEvent?(.userStartedSpeaking)
                case "conversation.user.stopped_speaking":
                    onAvatarEvent?(.userStoppedSpeaking)
                default:
                    break
                }
            }

        default:
            break
        }
    }

    // MARK: Swift → JS (used by TavusCVIView.Coordinator after claiming)

    func sendContextUpdate(_ context: String) {
        let escaped = context
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView?.evaluateJavaScript("sendContextUpdate('\(escaped)');", completionHandler: nil)
    }

    func sendEcho(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView?.evaluateJavaScript("sendEcho('\(escaped)');", completionHandler: nil)
    }

    func sendInterrupt() {
        webView?.evaluateJavaScript("sendInterrupt();", completionHandler: nil)
    }

    // MARK: Navigation Errors

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[TavusPreload] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[TavusPreload] Load failed: \(error.localizedDescription)")
    }
}

// MARK: - Errors

enum TavusError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case conversationNotActive

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Tavus API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from avatar service."
        case .apiError(let code, _) where code == 429:
            return "Avatar service is busy. Please try again in a moment."
        case .apiError(let code, _) where code == 402:
            return "Avatar session limit reached. Please try again later."
        case .apiError(let code, _) where (500...599).contains(code):
            return "Avatar service is temporarily unavailable."
        case .apiError(let code, let message):
            return "Avatar connection failed (\(code)): \(message)"
        case .conversationNotActive:
            return "No active conversation."
        }
    }
}
