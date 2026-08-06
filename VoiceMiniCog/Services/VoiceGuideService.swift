//
//  VoiceGuideService.swift
//  VoiceMiniCog
//
//  Voice-mode replacement for DailyCallManager: subscribes to the SAME
//  NotificationCenter seam the phase views already use (avatarSpeak /
//  avatarInterrupt / silence watch), plays pre-rendered clips from
//  VoiceClipLibrary, and posts .avatarStartedSpeaking /
//  .avatarDoneSpeaking so phase-view pacing works unchanged.
//
//  Runtime speech is a CLOSED SET: bundled clips (hash-verified) with an
//  AVSpeechSynthesizer fallback for unexpected text (logged, no PHI).
//  Exactly one of {VoiceGuideService, DailyCallManager} is active per
//  session — see GuideMode.
//

import AVFoundation
import Foundation
import os.log

@MainActor
@Observable
final class VoiceGuideService: NSObject {

    private static let log = Logger(subsystem: "com.mercycog.VoiceMiniCog",
                                    category: "VoiceGuide")

    // MARK: State

    /// True while a clip (or fallback utterance) is playing. Observable so
    /// voice-mode UI can render a speaking indicator.
    private(set) var isSpeaking = false

    /// Recorded mic-mute state. Phase views own SpeechService capture; this
    /// only mirrors what .tavusMicMuteRequest asked for.
    private(set) var micMuted = true

    @ObservationIgnored private let library: VoiceClipLibrary
    @ObservationIgnored private let playbackDisabledForTesting: Bool

    /// The notification seam. Production always uses .default (the center
    /// phase views post through); tests may inject a private center so
    /// service-emitted notifications (.sessionAbandoned in particular) do not
    /// reach the test HOST APP's ContentView — a real .sessionAbandoned there
    /// tears down AvatarAssessmentCanvas, whose AvatarLayoutManager deinit
    /// crashes on the Xcode 26.2 MainActor-deinit back-deploy bug (see
    /// VoiceClipLibrary's header comment; crash report 2026-08-05-204055.ips).
    @ObservationIgnored private let center: NotificationCenter

    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var fallbackSynth: AVSpeechSynthesizer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    // Silence watchdog (mirrors DailyCallManager 90s/150s semantics)
    @ObservationIgnored private var reengagementTask: Task<Void, Never>?
    @ObservationIgnored private var abandonmentTask: Task<Void, Never>?
    @ObservationIgnored private var silenceStartedAt: Date?
    @ObservationIgnored private let reengagementAfter: TimeInterval
    @ObservationIgnored private let abandonmentAfter: TimeInterval

    /// - Parameters:
    ///   - playbackDisabledForTesting: completes each utterance synchronously
    ///     without touching AVAudioPlayer/AVSpeechSynthesizer.
    ///   - reengagementAfter/abandonmentAfter: watchdog intervals. Production
    ///     callers use the defaults (90 s / 150 s, same as DailyCallManager);
    ///     tests inject sub-second values so the fire path is measurable.
    init(library: VoiceClipLibrary,
         playbackDisabledForTesting: Bool = false,
         reengagementAfter: TimeInterval = 90.0,
         abandonmentAfter: TimeInterval = 150.0,
         notificationCenter: NotificationCenter = .default) {
        self.library = library
        self.playbackDisabledForTesting = playbackDisabledForTesting
        self.reengagementAfter = reengagementAfter
        self.abandonmentAfter = abandonmentAfter
        self.center = notificationCenter
        super.init()
    }

    // MARK: Activation

    func activate() {
        guard observers.isEmpty else { return }
        // Voice mode has no Daily join, so nobody else configures the audio
        // session. MUST be the playAndRecord config: SpeechService assumes the
        // session is already .playAndRecord and never configures it itself
        // (SpeechService.swift:135-140). configureForRealtimeVoice() is
        // idempotent (isConfigured guard) and covers AVAudioPlayer playback
        // AND mic capture. Do NOT use configureForPlaybackOnly() — category
        // .playback kills SpeechService capture.
        try? AudioSessionManager.shared.configureForRealtimeVoice()
        // Observers run synchronously via MainActor.assumeIsolated — the same
        // pattern DailyCallManager uses (DailyCallManager.swift:1061-1108).
        // queue: .main guarantees the block executes on the main thread, and
        // synchronous handling keeps clip start inside the same run-loop turn
        // as the avatarSpeak() call (<50 ms latency goal).
        let nc = center
        observers = [
            nc.addObserver(forName: .tavusEchoRequest, object: nil, queue: .main) { [weak self] note in
                guard let text = note.userInfo?["text"] as? String else { return }
                MainActor.assumeIsolated { self?.speak(text) }
            },
            nc.addObserver(forName: .tavusRespondRequest, object: nil, queue: .main) { [weak self] note in
                guard let text = note.userInfo?["text"] as? String else { return }
                MainActor.assumeIsolated { self?.speak(text) }
            },
            nc.addObserver(forName: .tavusInterruptRequest, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.interrupt() }
            },
            nc.addObserver(forName: .tavusMicMuteRequest, object: nil, queue: .main) { [weak self] note in
                guard let muted = note.userInfo?["muted"] as? Bool else { return }
                MainActor.assumeIsolated { self?.micMuted = muted }
            },
            nc.addObserver(forName: .tavusBeginSilenceWatchRequest, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.armSilenceWatch() }
            },
            nc.addObserver(forName: .tavusCancelSilenceWatchRequest, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelSilenceWatch() }
            },
            // Patient speech cancels the watchdog, same as the Daily path.
            // (Live once Task 4B's SpeechService bridge posts this in voice mode.)
            nc.addObserver(forName: .patientStartedSpeaking, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelSilenceWatch() }
            },
            // .tavusContextUpdate / .tavusPhaseTypeRequest: intentionally not
            // observed — LLM-context concepts with no voice-mode equivalent.
        ]
        Self.log.info("VoiceGuideService activated")
    }

    func deactivate() {
        observers.forEach(center.removeObserver(_:))
        observers = []
        interrupt(postDone: false)
        cancelSilenceWatch()
        Self.log.info("VoiceGuideService deactivated")
    }

    // MARK: Speaking

    private func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.append(trimmed)
        playNextIfIdle()
    }

    private func playNextIfIdle() {
        guard !isSpeaking, !queue.isEmpty else { return }
        let text = queue.removeFirst()
        isSpeaking = true
        center.post(name: .avatarStartedSpeaking, object: nil)

        if playbackDisabledForTesting {
            spokenTextsForTesting.append(text)
            finishCurrentUtterance()
            return
        }

        if let clip = library.entry(forText: text),
           let url = library.clipURL(for: clip) {
            playClip(at: url, id: clip.id)
        } else {
            // Closed-set miss: fall back to on-device synthesis so the
            // assessment never blocks. A missing clip degrades to synthesized
            // EXACT text — never to a different clip. Log the miss WITHOUT
            // the text (scripts are not PHI, but keep logs content-free).
            Self.log.fault("Clip miss (hash=\(VoiceClipLibrary.sha256(of: text), privacy: .public)) — AVSpeech fallback")
            speakWithFallbackSynth(text)
        }
    }

    private func playClip(at url: URL, id: String) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            player = p
            p.play()
            Self.log.info("Playing clip \(id, privacy: .public)")
        } catch {
            Self.log.error("AVAudioPlayer failed: \(error.localizedDescription, privacy: .public)")
            finishCurrentUtterance()
        }
    }

    private func speakWithFallbackSynth(_ text: String) {
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        fallbackSynth = synth
        let utterance = AVSpeechUtterance(string: VoiceClipLibrary.normalize(text))
        utterance.rate = 0.45          // ≈130-140 wpm per behavioral guide
        utterance.preUtteranceDelay = 0.1
        synth.speak(utterance)
    }

    /// Completes the utterance that is currently speaking. The isSpeaking
    /// guard makes this idempotent: after interrupt() has already torn the
    /// utterance down, a late delegate callback (AVSpeechSynthesizer posts
    /// didCancel from stopSpeaking; a stale Task hop can arrive after
    /// interrupt) must NOT post a second .avatarDoneSpeaking — phase views
    /// pace on that notification and a duplicate could unlock a listening
    /// window for speech that never played.
    private func finishCurrentUtterance() {
        guard isSpeaking else { return }
        isSpeaking = false
        player = nil
        fallbackSynth = nil
        if queue.isEmpty {
            center.post(name: .avatarDoneSpeaking, object: nil)
        } else {
            playNextIfIdle()
        }
    }

    /// Stop playback and clear the queue. Posts .avatarDoneSpeaking only when
    /// there was actually something to cancel (speaking, or a non-empty
    /// queue). An idle interrupt posts NOTHING — matching avatar mode, where
    /// conversation.interrupt on a silent replica produces no stopped_speaking
    /// event. Every phase view calls avatarInterrupt() in onAppear
    /// (e.g. QAPhaseView.swift:52) before speaking; a spurious done there
    /// could trip .avatarDoneSpeaking handlers before the first prompt plays.
    private func interrupt(postDone: Bool = true) {
        let hadWork = isSpeaking || !queue.isEmpty
        queue.removeAll()
        player?.stop()          // AVAudioPlayer.stop() does NOT fire the delegate
        player = nil
        isSpeaking = false      // clear BEFORE stopSpeaking so didCancel's
                                // finishCurrentUtterance no-ops (guard above)
        fallbackSynth?.stopSpeaking(at: .immediate)
        fallbackSynth = nil
        if postDone && hadWork {
            center.post(name: .avatarDoneSpeaking, object: nil)
        }
    }

    // MARK: Silence watchdog

    private func armSilenceWatch() {
        cancelSilenceWatch()
        silenceStartedAt = Date()
        reengagementTask = Task { [weak self] in
            let nanos = UInt64((self?.reengagementAfter ?? 90.0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            self.speak(VoiceRefusalCopy.reengagement.text)
        }
        abandonmentTask = Task { [weak self] in
            let nanos = UInt64((self?.abandonmentAfter ?? 150.0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            self.fireAbandonment()
        }
    }

    private func fireAbandonment() {
        guard let started = silenceStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        Self.log.warning("Silence watchdog: \(elapsed, privacy: .public)s elapsed — session abandoned")
        cancelSilenceWatch()
        // Shape verified against DailyCallManager.swift:808-815 —
        // ContentView parses reason via SessionShutdownReason(rawValue:).
        center.post(
            name: .sessionAbandoned, object: nil,
            userInfo: [
                "reason": SessionShutdownReason.abandonedSilence.rawValue,
                "silenceDuration": elapsed,
            ])
    }

    private func cancelSilenceWatch() {
        silenceStartedAt = nil
        reengagementTask?.cancel(); reengagementTask = nil
        abandonmentTask?.cancel(); abandonmentTask = nil
    }

    // MARK: Test hooks

    func enqueueForTesting(_ texts: [String]) { queue.append(contentsOf: texts) }
    var queueDepthForTesting: Int { queue.count }
    var silenceWatchArmedForTesting: Bool {
        reengagementTask != nil || abandonmentTask != nil
    }
    /// Utterances in playback order. Only recorded when
    /// playbackDisabledForTesting — order/duplication proof for clinical
    /// scripts (a reordered queue = instructions out of order).
    @ObservationIgnored private(set) var spokenTextsForTesting: [String] = []
}

// MARK: - AVAudioPlayerDelegate

extension VoiceGuideService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                                 successfully flag: Bool) {
        Task { @MainActor in self.finishCurrentUtterance() }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceGuideService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishCurrentUtterance() }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishCurrentUtterance() }
    }
}
