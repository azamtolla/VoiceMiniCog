//
//  AvatarStreamService.swift
//  VoiceMiniCog
//

import Foundation
import AVFoundation

enum AvatarAssistantState: String {
    case idle
    case speaking
    case listening
    case thinking
}

struct AvatarTransportMetrics {
    var reconnectCount: Int = 0
    var droppedFrameCount: Int = 0
    var lastRoundTripMs: Double?
}

@Observable
final class AvatarStreamService {
    // MARK: - Published State

    var isConnected: Bool = false
    var assistantState: AvatarAssistantState = .idle
    var transcriptPreview: String = ""
    var blendshapes: [String: Float] = [:]
    var metrics: AvatarTransportMetrics = .init()
    var errorBannerMessage: String?
    var isVoiceOnlyFallback: Bool = false

    // MARK: - Socket/Transport

    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?
    private var isManuallyDisconnected = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5

    // MARK: - Audio Capture

    private let micEngine = AVAudioEngine()
    private let sampleRate: Double = 16_000
    private let monoChannelCount: AVAudioChannelCount = 1

    // MARK: - Audio Playback

    private let playbackEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private lazy var playbackFormat: AVAudioFormat? = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: monoChannelCount,
            interleaved: true
        )
    }()

    // MARK: - Metrics / RTT

    private var pingSentAt: Date?

    // MARK: - Decode Models

    private struct BlendshapeFrame: Codable {
        let blendshapes: [String: Float]
        let transcript: String?
        let state: String?
    }

    private struct AssistantAudioFrame {
        let payload: Data
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        setupPlayback()
    }

    // MARK: - Public Lifecycle

    func connect() {
        guard socketTask == nil else { return }
        isManuallyDisconnected = false
        errorBannerMessage = nil
        isVoiceOnlyFallback = false
        reconnectAttempt = 0

        guard let url = avatarWebSocketURL() else {
            errorBannerMessage = "Avatar endpoint unavailable. Using standard assessment view."
            return
        }

        let task = session.webSocketTask(with: url)
        socketTask = task
        task.resume()

        Task { @MainActor in
            self.isConnected = true
            self.assistantState = .listening
        }

        receiveLoop()
        startPingLoop()
    }

    func disconnect() {
        isManuallyDisconnected = true
        stopMicStreaming()
        reconnectTask?.cancel()
        reconnectTask = nil
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        isConnected = false
        assistantState = .idle
    }

    func startMicStreaming() {
        guard let socketTask else { return }
        if micEngine.isRunning { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setPreferredSampleRate(sampleRate)
            try audioSession.setPreferredInputNumberOfChannels(Int(monoChannelCount))
            try audioSession.setActive(true)

            let inputNode = micEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard let targetFormat = playbackFormat else { return }
            guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                errorBannerMessage = "Audio converter unavailable."
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self else { return }
                guard let pcmData = self.convertToPCM16Mono16k(buffer: buffer, converter: converter, targetFormat: targetFormat) else {
                    Task { @MainActor in
                        self.metrics.droppedFrameCount += 1
                    }
                    return
                }
                socketTask.send(.data(pcmData)) { [weak self] error in
                    if error != nil {
                        Task { @MainActor in
                            self?.metrics.droppedFrameCount += 1
                        }
                    }
                }
            }

            micEngine.prepare()
            try micEngine.start()
            assistantState = .listening
        } catch {
            errorBannerMessage = "Microphone stream failed: \(error.localizedDescription)"
        }
    }

    func stopMicStreaming() {
        if micEngine.inputNode.numberOfInputs > 0 {
            micEngine.inputNode.removeTap(onBus: 0)
        }
        if micEngine.isRunning {
            micEngine.stop()
        }
    }

    // MARK: - Private URL/Connection Helpers

    private func avatarWebSocketURL() -> URL? {
        guard var components = URLComponents(string: APIClient.baseURL) else { return nil }
        if components.scheme == "https" {
            components.scheme = "wss"
        } else {
            components.scheme = "ws"
        }
        components.path = "/avatar"
        return components.url
    }

    private func scheduleReconnectIfNeeded() {
        guard !isManuallyDisconnected else { return }
        guard reconnectAttempt < maxReconnectAttempts else {
            errorBannerMessage = "Avatar connection failed. You can continue with the standard assessment view."
            isConnected = false
            return
        }

        reconnectAttempt += 1
        metrics.reconnectCount = reconnectAttempt

        let delaySeconds = min(pow(2.0, Double(reconnectAttempt)), 12.0)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let self else { return }
            if self.socketTask == nil && !self.isManuallyDisconnected {
                self.connect()
            }
        }
    }

    private func receiveLoop() {
        socketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                Task { @MainActor in
                    self.isConnected = false
                }
                self.socketTask = nil
                self.scheduleReconnectIfNeeded()
            case .success(let message):
                self.handle(message: message)
                self.receiveLoop()
            }
        }
    }

    private func startPingLoop() {
        Task.detached { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let task = self.socketTask else { break }
                let sent = Date()
                self.pingSentAt = sent
                task.sendPing { [weak self] error in
                    guard let self, error == nil else { return }
                    if let pingSentAt = self.pingSentAt {
                        let rtt = Date().timeIntervalSince(pingSentAt) * 1000
                        Task { @MainActor in
                            self.metrics.lastRoundTripMs = rtt
                        }
                    }
                }
            }
        }
    }

    // MARK: - Message Handling

    private func handle(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let payload):
            handleIncomingAudioFrame(AssistantAudioFrame(payload: payload))
        case .string(let text):
            handleIncomingJSON(text)
        @unknown default:
            break
        }
    }

    private func handleIncomingAudioFrame(_ frame: AssistantAudioFrame) {
        Task { @MainActor in
            self.assistantState = .speaking
        }
        schedulePlayback(frame.payload)
    }

    private func handleIncomingJSON(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        do {
            let decoded = try JSONDecoder().decode(BlendshapeFrame.self, from: data)
            Task { @MainActor in
                self.blendshapes = decoded.blendshapes
                if let transcript = decoded.transcript, !transcript.isEmpty {
                    self.transcriptPreview = transcript
                }
                if let state = decoded.state {
                    self.assistantState = AvatarAssistantState(rawValue: state) ?? self.assistantState
                }
            }
        } catch {
            Task { @MainActor in
                // Blendshape decode can fail independently of audio; continue voice-only mode.
                self.isVoiceOnlyFallback = true
            }
        }
    }

    // MARK: - Audio Conversion / Playback

    private func convertToPCM16Mono16k(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) -> Data? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            return nil
        }

        var sourceConsumed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if sourceConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            sourceConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        guard error == nil else { return nil }
        guard let int16Channel = outputBuffer.int16ChannelData?.pointee else { return nil }
        let sampleCount = Int(outputBuffer.frameLength)
        return Data(bytes: int16Channel, count: sampleCount * MemoryLayout<Int16>.size)
    }

    private func setupPlayback() {
        playbackEngine.attach(playerNode)
        let mixer = playbackEngine.mainMixerNode
        if let format = playbackFormat {
            playbackEngine.connect(playerNode, to: mixer, format: format)
        } else {
            playbackEngine.connect(playerNode, to: mixer, format: nil)
        }

        do {
            try playbackEngine.start()
            playerNode.play()
        } catch {
            errorBannerMessage = "Playback engine failed: \(error.localizedDescription)"
        }
    }

    private func schedulePlayback(_ rawPCM16: Data) {
        guard let format = playbackFormat else { return }
        let bytesPerFrame = MemoryLayout<Int16>.size * Int(format.channelCount)
        guard bytesPerFrame > 0 else { return }
        let frameCount = AVAudioFrameCount(rawPCM16.count / bytesPerFrame)
        guard frameCount > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        rawPCM16.withUnsafeBytes { sourcePtr in
            guard let srcBase = sourcePtr.baseAddress else { return }
            if let channelData = buffer.int16ChannelData {
                memcpy(channelData.pointee, srcBase, rawPCM16.count)
            }
        }

        playerNode.scheduleBuffer(buffer, completionHandler: { [weak self] in
            Task { @MainActor in
                if self?.assistantState == .speaking {
                    self?.assistantState = .listening
                }
            }
        })
    }
}
