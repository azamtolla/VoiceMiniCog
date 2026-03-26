//
//  PersonaPlexService.swift
//  VoiceMiniCog
//
//  Connects to the Avatar Gateway via WebSocket.
//  Streams 24 kHz PCM mic audio up, plays back response audio
//  in real-time, accumulates text tokens, and drives lip-sync
//  blendshapes from the received audio.
//
//  Protocol (iOS ↔ Gateway):
//    Binary messages  = raw PCM16 audio (24 kHz, mono, no prefix)
//    Text messages    = JSON commands/prompts
//

import Foundation
import AVFoundation
import Combine

// MARK: - PersonaPlexService

@MainActor
final class PersonaPlexService: ObservableObject {

    // MARK: Published state (consumed by MiniCogLiveView)

    @Published var blendshapes: [String: Float] = [:]
    @Published var assistantState: AssistantState = .idle
    @Published var lastTranscript: String = ""
    @Published var isConnected: Bool = false
    @Published var lastError: String?
    @Published var reconnectCount: Int = 0
    @Published var lastClipDonePhase: String = ""
    @Published var lastRepeatCount: Int = 0
    @Published var repeatLimitReached: Bool = false
    @Published var repeatLimitPhase: String = ""

    // MARK: Audio formats

    /// PersonaPlex wire format: 24 kHz mono PCM16
    private let serverFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    /// Float32 equivalent for player node (mixer requires float32)
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    // MARK: Private state

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var endpointURL: URL?

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var micConverter: AVAudioConverter?
    private var isEngineRunning = false
    private var isMicStreaming  = false
    private var isReceiving    = false
    private var isConnecting   = false

    // Lip sync
    private let lipSync = AudioLipSync()
    private var displayLink: CADisplayLink?
    private var pendingLipSyncAudio: [Float] = []
    private let lipLock = NSLock()

    // Transcript accumulator
    private var transcriptBuffer = ""

    private static let maxReconnectAttempts = 5

    // MARK: - Public API

    func connect(to url: URL) {
        guard !isConnecting else { return }
        isConnecting = true

        disconnect()
        endpointURL = url
        assistantState = .thinking
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            let micGranted = await self.ensureMicPermission()
            self.continueConnect(to: url, micGranted: micGranted)
        }
    }

    private func ensureMicPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    private func continueConnect(to url: URL, micGranted: Bool) {
        do {
            try configureAudioSession()
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
            isConnecting = false
            return
        }

        prepareAudioNodes()

        let delegate = PermissiveSSLDelegate()
        urlSession = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )

        let task = urlSession!.webSocketTask(with: url)
        webSocket = task
        task.resume()
        print("[PP] Connecting to \(url.absoluteString)")

        task.sendPing { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnecting = false

                if let error {
                    self.lastError = "Connection failed: \(error.localizedDescription)"
                    self.assistantState = .idle
                    self.retryIfNeeded()
                    return
                }

                self.isConnected = true
                self.startEngineAndMic(micGranted: micGranted)
                self.receiveLoop()
                self.assistantState = .listening
                print("[PP] Connected and streaming")
            }
        }
    }

    func disconnect() {
        stopMic()
        stopLipSync()
        teardownAudioEngine()
        deactivateAudioSession()

        isReceiving = false
        isConnecting = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        urlSession = nil

        isConnected = false
        assistantState = .idle
        transcriptBuffer = ""
    }

    func sendPrompt(_ text: String) {
        guard let ws = webSocket else { return }
        let cmd: [String: Any] = ["command": "prompt", "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: cmd),
              let json = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(json)) { err in
            if let err { print("[PP] prompt send error: \(err)") }
        }
    }

    func sendPhaseCommand(phase: String, words: [String] = [], wordSetIndex: Int? = nil) {
        guard let ws = webSocket else { return }
        var cmd: [String: Any] = [
            "command": "set_phase",
            "phase": phase,
        ]
        if !words.isEmpty { cmd["words"] = words }
        if let idx = wordSetIndex { cmd["word_set_index"] = idx }
        guard let data = try? JSONSerialization.data(withJSONObject: cmd),
              let json = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(json)) { err in
            if let err { print("[PP] phase command error: \(err)") }
        }
        repeatLimitReached = false
        repeatLimitPhase = ""
    }

    func requestRepeat(for phase: String) {
        guard let ws = webSocket else { return }
        let cmd: [String: Any] = [
            "command": "repeat_clip",
            "phase": phase,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: cmd),
              let json = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(json)) { err in
            if let err { print("[PP] repeat error: \(err)") }
        }
    }

    func recycleMoshi(prompt: String, phase: String = "") {
        guard let ws = webSocket else { return }
        var cmd: [String: Any] = [
            "command": "recycle_moshi",
            "text_prompt": prompt,
        ]
        if !phase.isEmpty { cmd["phase"] = phase }
        guard let data = try? JSONSerialization.data(withJSONObject: cmd),
              let json = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(json)) { _ in }
    }

    // MARK: - Audio Session (must be called BEFORE engine operations)

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    // MARK: - Audio Engine Lifecycle

    private func prepareAudioNodes() {
        guard audioEngine == nil else { return }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        audioEngine = engine
        playerNode = player
    }

    private func teardownAudioEngine() {
        stopMic()

        if let player = playerNode, player.isPlaying {
            player.stop()
        }
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }

        playerNode = nil
        audioEngine = nil
        micConverter = nil
        isEngineRunning = false
    }

    // MARK: - Mic Capture → Server

    private func startEngineAndMic(micGranted: Bool) {
        guard let engine = audioEngine, let player = playerNode else { return }
        guard !isEngineRunning else { return }

        if micGranted, let ws = webSocket {
            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)

            let inputFormat = inputNode.outputFormat(forBus: 0)

            if inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
               let converter = AVAudioConverter(from: inputFormat, to: serverFormat) {
                converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
                micConverter = converter

                let sampleRateRatio = serverFormat.sampleRate / inputFormat.sampleRate
                let captureWS = ws

                inputNode.installTap(onBus: 0, bufferSize: 960, format: inputFormat) {
                    [weak self] buffer, _ in
                    guard let self else { return }
                    guard let pcm16Data = self.convertMicToPCM16(
                        buffer: buffer,
                        converter: converter,
                        sampleRateRatio: sampleRateRatio
                    ) else { return }

                    captureWS.send(.data(pcm16Data)) { err in
                        if let err { print("[PP] mic send err: \(err.localizedDescription)") }
                    }
                }

                do {
                    try engine.start()
                    player.play()
                    isEngineRunning = true
                    isMicStreaming = true
                    print("[PP] Engine+mic at \(inputFormat.sampleRate) Hz → 24 kHz")
                    return
                } catch {
                    print("[PP] Engine+mic failed: \(error) — falling back to playback")
                    inputNode.removeTap(onBus: 0)
                }
            } else {
                print("[PP] Mic format invalid (\(inputFormat)) — playback only")
            }
        } else {
            print("[PP] Mic not granted — playback only")
        }

        do {
            try engine.start()
            player.play()
            isEngineRunning = true
            print("[PP] Engine started (playback only)")
        } catch {
            lastError = "Audio engine: \(error.localizedDescription)"
        }
    }

    private nonisolated func convertMicToPCM16(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        sampleRateRatio: Double
    ) -> Data? {
        let outFrames = max(AVAudioFrameCount(Double(buffer.frameLength) * sampleRateRatio), 1)
        guard let outBuf = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outFrames
        ) else { return nil }

        var nsError: NSError?
        var consumed = false

        let status = converter.convert(to: outBuf, error: &nsError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status == .haveData, nsError == nil else { return nil }

        let byteCount = Int(outBuf.frameLength) * MemoryLayout<Int16>.size
        guard byteCount > 0, let int16 = outBuf.int16ChannelData?.pointee else { return nil }
        return Data(bytes: int16, count: byteCount)
    }

    private func stopMic() {
        guard isMicStreaming else { return }
        audioEngine?.inputNode.removeTap(onBus: 0)
        isMicStreaming = false
    }

    // MARK: - Receive Loop

    private func receiveLoop() {
        guard let ws = webSocket, !isReceiving else { return }
        isReceiving = true

        func next() {
            ws.receive { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch result {
                    case .success(let msg):
                        self.handleMessage(msg)
                        next()
                    case .failure(let err):
                        self.isReceiving = false
                        self.isConnected = false
                        self.lastError = "Receive: \(err.localizedDescription)"
                        self.assistantState = .idle
                        self.retryIfNeeded()
                    }
                }
            }
        }
        next()
    }

    // MARK: - Message Dispatch

    private func handleMessage(_ msg: URLSessionWebSocketTask.Message) {
        switch msg {
        case .data(let data):
            handleBinaryMessage(data)
        case .string(let text):
            handleTextMessage(text)
        @unknown default:
            return
        }
    }

    private func handleBinaryMessage(_ data: Data) {
        guard data.count >= 2 else { return }
        playServerAudio(data)
        feedLipSync(data)
        if assistantState != .speaking { assistantState = .speaking }
    }

    private func handleTextMessage(_ text: String) {
        guard let jsonData = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return }

        if let stateStr = json["state"] as? String, stateStr == "clip_done" {
            let phase = json["phase"] as? String ?? ""
            lastClipDonePhase = phase
            lastRepeatCount = (json["repeat_count"] as? Int) ?? 0
            assistantState = .listening
            print("[PP] Clip done: \(phase) (repeat \(lastRepeatCount))")
            return
        }

        if let stateStr = json["state"] as? String, stateStr == "repeat_limit_reached" {
            let phase = json["phase"] as? String ?? ""
            repeatLimitReached = true
            repeatLimitPhase = phase
            print("[PP] Repeat limit reached: \(phase)")
            return
        }

        if let values = json["values"] as? [String: Double] {
            var floatDict: [String: Float] = [:]
            for (k, v) in values { floatDict[k] = Float(v) }
            blendshapes = floatDict
        }

        if let stateStr = json["state"] as? String {
            switch stateStr {
            case "speaking":  assistantState = .speaking
            case "listening": assistantState = .listening
            case "thinking":  assistantState = .thinking
            default: break
            }
        }

        if let transcript = json["transcript"] as? String, !transcript.isEmpty {
            lastTranscript = transcript
        }

        if let error = json["error"] as? String, !error.isEmpty {
            lastError = error
        }
    }

    // MARK: - Audio Playback (PCM16 → float32 → playerNode)

    private func playServerAudio(_ payload: Data) {
        guard isEngineRunning, let playerNode else { return }

        let byteCount = payload.count
        guard byteCount >= 2 else { return }

        let frameCount = byteCount / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return }

        guard let floatBuffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }
        floatBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let dstFloat = floatBuffer.floatChannelData?.pointee else { return }

        payload.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<frameCount {
                dstFloat[i] = Float(src[i]) / 32768.0
            }
        }

        playerNode.scheduleBuffer(floatBuffer)
    }

    // MARK: - Lip Sync

    private func feedLipSync(_ payload: Data) {
        let sampleCount = payload.count / 2
        guard sampleCount > 0 else { return }

        let raw = Array(payload)
        var floats = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let lo = UInt16(raw[i * 2])
            let hi = UInt16(raw[i * 2 + 1])
            let s  = Int16(bitPattern: lo | (hi << 8))
            floats[i] = Float(s) / 32767.0
        }

        lipLock.lock()
        pendingLipSyncAudio.append(contentsOf: floats)
        let maxSamples = Int(24_000 * 0.05)
        if pendingLipSyncAudio.count > maxSamples {
            pendingLipSyncAudio = Array(pendingLipSyncAudio.suffix(maxSamples))
        }
        lipLock.unlock()

        startLipSyncIfNeeded()
    }

    private func startLipSyncIfNeeded() {
        guard displayLink == nil else { return }
        let target = DisplayLinkTarget { [weak self] in self?.tickLipSync() }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopLipSync() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func tickLipSync() {
        lipLock.lock()
        let audio = pendingLipSyncAudio
        lipLock.unlock()

        let frame: BlendshapeFrame
        if !audio.isEmpty && assistantState == .speaking {
            frame = lipSync.process(pcm: audio)
        } else {
            frame = lipSync.idleFrame()
        }

        blendshapes = frame.dictionary
    }

    // MARK: - Reconnect with backoff + limit

    private func retryIfNeeded() {
        guard let url = endpointURL else { return }
        guard reconnectCount < Self.maxReconnectAttempts else {
            lastError = "Gave up after \(Self.maxReconnectAttempts) reconnect attempts"
            return
        }
        reconnectCount += 1
        let delay = min(8.0, pow(2.0, Double(reconnectCount)))

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !self.isConnected, !self.isConnecting else { return }
            self.connect(to: url)
        }
    }
}

// MARK: - SSL Delegate (accept RunPod self-signed certs)

private class PermissiveSSLDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

// MARK: - CADisplayLink target

private class DisplayLinkTarget: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func tick() { block() }
}
