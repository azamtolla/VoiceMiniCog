//
//  AudioLipSync.swift
//  VoiceMiniCog
//
//  FFT-based lip sync: extracts 4 frequency bands from PCM audio,
//  maps to 6 viseme classes, blends into ARKit-compatible blendshape weights.
//
//  Viseme model:
//    silence   — mouth at rest
//    open      — aa, ah, aw (low F0, strong band 0-1)
//    round     — oo, w, u  (strong band 1, weak band 2)
//    wide      — ee, ih, eh (strong band 2)
//    closed    — m, b, p   (low energy overall, brief closure)
//    fricative — s, sh, f  (strong band 3)
//

import Foundation
import Accelerate

// MARK: - Blendshape Snapshot

struct BlendshapeFrame {
    var jawOpen: Float = 0
    var mouthClose: Float = 0
    var mouthFunnel: Float = 0
    var mouthPucker: Float = 0
    var mouthLeft: Float = 0
    var mouthRight: Float = 0
    var mouthSmileLeft: Float = 0
    var mouthSmileRight: Float = 0
    var mouthFrownLeft: Float = 0
    var mouthFrownRight: Float = 0
    var mouthDimpleLeft: Float = 0
    var mouthDimpleRight: Float = 0
    var mouthStretchLeft: Float = 0
    var mouthStretchRight: Float = 0
    var mouthRollLower: Float = 0
    var mouthRollUpper: Float = 0
    var mouthShrugLower: Float = 0
    var mouthShrugUpper: Float = 0
    var mouthPressLeft: Float = 0
    var mouthPressRight: Float = 0
    var mouthLowerDownLeft: Float = 0
    var mouthLowerDownRight: Float = 0
    var mouthUpperUpLeft: Float = 0
    var mouthUpperUpRight: Float = 0
    var browDownLeft: Float = 0
    var browDownRight: Float = 0
    var browInnerUp: Float = 0
    var browOuterUpLeft: Float = 0
    var browOuterUpRight: Float = 0
    var cheekPuff: Float = 0
    var cheekSquintLeft: Float = 0
    var cheekSquintRight: Float = 0
    var noseSneerLeft: Float = 0
    var noseSneerRight: Float = 0
    var eyeBlinkLeft: Float = 0
    var eyeBlinkRight: Float = 0
    var eyeSquintLeft: Float = 0
    var eyeSquintRight: Float = 0
    var eyeWideLeft: Float = 0
    var eyeWideRight: Float = 0

    var dictionary: [String: Float] {
        [
            "jawOpen": jawOpen, "mouthClose": mouthClose,
            "mouthFunnel": mouthFunnel, "mouthPucker": mouthPucker,
            "mouthLeft": mouthLeft, "mouthRight": mouthRight,
            "mouthSmileLeft": mouthSmileLeft, "mouthSmileRight": mouthSmileRight,
            "mouthFrownLeft": mouthFrownLeft, "mouthFrownRight": mouthFrownRight,
            "mouthDimpleLeft": mouthDimpleLeft, "mouthDimpleRight": mouthDimpleRight,
            "mouthStretchLeft": mouthStretchLeft, "mouthStretchRight": mouthStretchRight,
            "mouthRollLower": mouthRollLower, "mouthRollUpper": mouthRollUpper,
            "mouthShrugLower": mouthShrugLower, "mouthShrugUpper": mouthShrugUpper,
            "mouthPressLeft": mouthPressLeft, "mouthPressRight": mouthPressRight,
            "mouthLowerDownLeft": mouthLowerDownLeft, "mouthLowerDownRight": mouthLowerDownRight,
            "mouthUpperUpLeft": mouthUpperUpLeft, "mouthUpperUpRight": mouthUpperUpRight,
            "browDownLeft": browDownLeft, "browDownRight": browDownRight,
            "browInnerUp": browInnerUp,
            "browOuterUpLeft": browOuterUpLeft, "browOuterUpRight": browOuterUpRight,
            "cheekPuff": cheekPuff,
            "cheekSquintLeft": cheekSquintLeft, "cheekSquintRight": cheekSquintRight,
            "noseSneerLeft": noseSneerLeft, "noseSneerRight": noseSneerRight,
            "eyeBlinkLeft": eyeBlinkLeft, "eyeBlinkRight": eyeBlinkRight,
            "eyeSquintLeft": eyeSquintLeft, "eyeSquintRight": eyeSquintRight,
            "eyeWideLeft": eyeWideLeft, "eyeWideRight": eyeWideRight,
        ]
    }
}

// MARK: - Viseme Weights

/// Weights for each of the 6 viseme classes (0-1 each). Sum does not need to be 1.
private struct VisemeWeights {
    var silence: Float = 0
    var open: Float = 0      // aa, ah
    var round: Float = 0     // oo, w
    var wide: Float = 0      // ee, ih
    var closed: Float = 0    // m, b, p
    var fricative: Float = 0 // s, sh, f
}

// MARK: - Audio Lip Sync Engine

class AudioLipSync {

    /// Asymmetric smoothing: fast attack, slow release (more natural jaw motion)
    var attackSmoothing: Float = 0.35
    var releaseSmoothing: Float = 0.65

    private var previous = BlendshapeFrame()
    private var lastBlinkTime: TimeInterval = 0
    private var nextBlinkInterval: TimeInterval = 3.0
    private var blinkPhase: Float = 0
    private var pendingBlink = false

    // FFT setup (512-point)
    private let fftSize = 512
    private var fftSetup: vDSP_DFT_Setup?

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    // MARK: - Public API

    func process(pcm: [Float]) -> BlendshapeFrame {
        let bands = computeFFTBands(pcm)
        let visemes = mapBandsToVisemes(bands)
        var frame = mapVisemesToBlendshapes(visemes)

        applyBlinks(&frame)
        applyIdleMotion(&frame)
        frame = smoothAsymmetric(current: frame, previous: previous)
        previous = frame
        return frame
    }

    func idleFrame() -> BlendshapeFrame {
        var frame = BlendshapeFrame()
        applyBlinks(&frame)
        applyIdleMotion(&frame)
        frame = smoothAsymmetric(current: frame, previous: previous)
        previous = frame
        return frame
    }

    // MARK: - FFT Band Extraction

    /// 4 frequency bands from real FFT:
    ///   band0: 0-300 Hz    (fundamental, voicing)
    ///   band1: 300-1000 Hz (first formant)
    ///   band2: 1-3 kHz     (second formant)
    ///   band3: 3-8 kHz     (fricatives, sibilants)
    private struct BandEnergies {
        var band0: Float = 0
        var band1: Float = 0
        var band2: Float = 0
        var band3: Float = 0
        var totalRMS: Float = 0
    }

    private func computeFFTBands(_ pcm: [Float]) -> BandEnergies {
        guard pcm.count >= fftSize, let setup = fftSetup else {
            // Fallback to RMS-only for short buffers
            var rms: Float = 0
            if !pcm.isEmpty { vDSP_rmsqv(pcm, 1, &rms, vDSP_Length(pcm.count)) }
            return BandEnergies(totalRMS: rms)
        }

        // Window the signal (Hann window reduces spectral leakage)
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        var input = Array(pcm.prefix(fftSize))
        vDSP.multiply(input, window, result: &windowed)

        // Real FFT via DFT
        var realIn = windowed
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)

        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        // Compute magnitude for each bin
        let halfN = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfN)
        for i in 0..<halfN {
            magnitudes[i] = sqrtf(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        // Bin resolution: assuming 24kHz sample rate
        // Each bin = 24000 / 512 ≈ 46.875 Hz
        let binHz: Float = 24000.0 / Float(fftSize)

        // Band boundaries in bins
        let b0End = Int(300.0 / binHz)          // ~6
        let b1End = Int(1000.0 / binHz)         // ~21
        let b2End = Int(3000.0 / binHz)         // ~64
        let b3End = min(Int(8000.0 / binHz), halfN) // ~170

        func bandEnergy(_ start: Int, _ end: Int) -> Float {
            guard end > start else { return 0 }
            let slice = Array(magnitudes[start..<end])
            var sum: Float = 0
            vDSP_sve(slice, 1, &sum, vDSP_Length(slice.count))
            return sum / Float(slice.count)
        }

        var rms: Float = 0
        vDSP_rmsqv(pcm, 1, &rms, vDSP_Length(min(pcm.count, fftSize)))

        return BandEnergies(
            band0: bandEnergy(1, b0End),
            band1: bandEnergy(b0End, b1End),
            band2: bandEnergy(b1End, b2End),
            band3: bandEnergy(b2End, b3End),
            totalRMS: rms
        )
    }

    // MARK: - Band → Viseme Mapping

    private func mapBandsToVisemes(_ bands: BandEnergies) -> VisemeWeights {
        let energy = min(bands.totalRMS * 3.0, 1.0)

        // Normalize band energies relative to total
        let total = bands.band0 + bands.band1 + bands.band2 + bands.band3 + 0.001
        let n0 = bands.band0 / total
        let n1 = bands.band1 / total
        let n2 = bands.band2 / total
        let n3 = bands.band3 / total

        var v = VisemeWeights()

        if energy < 0.05 {
            // Below voicing threshold → silence
            v.silence = 1.0
            return v
        }

        // Closed mouth (m, b, p): brief energy dip after voicing
        // Detected as low total energy with some band0
        if energy < 0.15 && n0 > 0.4 {
            v.closed = energy * 3.0
            return v
        }

        // Open (aa, ah): strong low frequency, dominant band0+band1
        v.open = min((n0 + n1 * 0.5) * energy * 2.0, 1.0)

        // Round (oo, w): band1 dominant, band2 weak
        v.round = min(n1 * (1.0 - n2) * energy * 2.5, 1.0)

        // Wide (ee, ih): band2 dominant
        v.wide = min(n2 * energy * 2.5, 1.0)

        // Fricative (s, sh, f): band3 dominant
        v.fricative = min(n3 * energy * 3.0, 1.0)

        return v
    }

    // MARK: - Viseme → Blendshape Poses

    private func mapVisemesToBlendshapes(_ v: VisemeWeights) -> BlendshapeFrame {
        var f = BlendshapeFrame()

        // Each viseme contributes to blendshapes proportionally to its weight

        // Open (aa, ah, aw)
        f.jawOpen += v.open * 0.65
        f.mouthLowerDownLeft += v.open * 0.45
        f.mouthLowerDownRight += v.open * 0.45
        f.mouthUpperUpLeft += v.open * 0.12
        f.mouthUpperUpRight += v.open * 0.12

        // Round (oo, w, u)
        f.jawOpen += v.round * 0.30
        f.mouthFunnel += v.round * 0.50
        f.mouthPucker += v.round * 0.40

        // Wide (ee, ih, eh)
        f.jawOpen += v.wide * 0.18
        f.mouthStretchLeft += v.wide * 0.35
        f.mouthStretchRight += v.wide * 0.35
        f.mouthSmileLeft += v.wide * 0.15
        f.mouthSmileRight += v.wide * 0.15

        // Closed (m, b, p)
        f.mouthClose += v.closed * 0.55
        f.mouthPressLeft += v.closed * 0.30
        f.mouthPressRight += v.closed * 0.30

        // Fricative (s, sh, f, th)
        f.jawOpen += v.fricative * 0.12
        f.mouthStretchLeft += v.fricative * 0.18
        f.mouthStretchRight += v.fricative * 0.18
        f.mouthUpperUpLeft += v.fricative * 0.08
        f.mouthUpperUpRight += v.fricative * 0.08

        // Silence — mouth at rest
        f.mouthClose += v.silence * 0.25

        // Subtle co-articulatory cheek/brow motion proportional to overall speech
        let totalSpeech = v.open + v.round + v.wide + v.fricative
        f.cheekSquintLeft += totalSpeech * 0.06
        f.cheekSquintRight += totalSpeech * 0.06
        f.browInnerUp += totalSpeech * 0.04

        return f
    }

    // MARK: - Blinks (suppress during active speech)

    private func applyBlinks(_ frame: inout BlendshapeFrame) {
        let now = ProcessInfo.processInfo.systemUptime

        // Schedule next blink
        if now - lastBlinkTime > nextBlinkInterval {
            if frame.jawOpen > 0.3 {
                // Speaking actively — defer blink
                pendingBlink = true
            } else {
                lastBlinkTime = now
                nextBlinkInterval = Double.random(in: 2.5...5.0)
                blinkPhase = 1.0
                pendingBlink = false
            }
        }

        // Fire pending blink when jaw closes
        if pendingBlink && frame.jawOpen < 0.15 {
            lastBlinkTime = ProcessInfo.processInfo.systemUptime
            nextBlinkInterval = Double.random(in: 2.5...5.0)
            blinkPhase = 1.0
            pendingBlink = false
        }

        if blinkPhase > 0 {
            frame.eyeBlinkLeft = blinkPhase
            frame.eyeBlinkRight = blinkPhase
            blinkPhase -= 0.15
            if blinkPhase < 0 { blinkPhase = 0 }
        }
    }

    // MARK: - Idle Motion

    private func applyIdleMotion(_ frame: inout BlendshapeFrame) {
        let t = Float(ProcessInfo.processInfo.systemUptime)
        frame.jawOpen += max(0, sin(t * 1.2) * 0.015)
        frame.browOuterUpLeft += sin(t * 0.7) * 0.012
        frame.browOuterUpRight += sin(t * 0.7 + 0.5) * 0.012
        frame.mouthSmileLeft += 0.04 + sin(t * 0.3) * 0.015
        frame.mouthSmileRight += 0.04 + sin(t * 0.3) * 0.015
    }

    // MARK: - Asymmetric Smoothing

    /// Fast attack (mouth opens quickly), slow release (mouth closes gently).
    private func smoothAsymmetric(current: BlendshapeFrame, previous: BlendshapeFrame) -> BlendshapeFrame {
        func s(_ cur: Float, _ prev: Float) -> Float {
            let factor = cur > prev ? attackSmoothing : releaseSmoothing
            return prev * factor + cur * (1.0 - factor)
        }

        var r = BlendshapeFrame()
        r.jawOpen = s(current.jawOpen, previous.jawOpen)
        r.mouthClose = s(current.mouthClose, previous.mouthClose)
        r.mouthFunnel = s(current.mouthFunnel, previous.mouthFunnel)
        r.mouthPucker = s(current.mouthPucker, previous.mouthPucker)
        r.mouthLeft = s(current.mouthLeft, previous.mouthLeft)
        r.mouthRight = s(current.mouthRight, previous.mouthRight)
        r.mouthSmileLeft = s(current.mouthSmileLeft, previous.mouthSmileLeft)
        r.mouthSmileRight = s(current.mouthSmileRight, previous.mouthSmileRight)
        r.mouthFrownLeft = s(current.mouthFrownLeft, previous.mouthFrownLeft)
        r.mouthFrownRight = s(current.mouthFrownRight, previous.mouthFrownRight)
        r.mouthStretchLeft = s(current.mouthStretchLeft, previous.mouthStretchLeft)
        r.mouthStretchRight = s(current.mouthStretchRight, previous.mouthStretchRight)
        r.mouthRollLower = s(current.mouthRollLower, previous.mouthRollLower)
        r.mouthRollUpper = s(current.mouthRollUpper, previous.mouthRollUpper)
        r.mouthLowerDownLeft = s(current.mouthLowerDownLeft, previous.mouthLowerDownLeft)
        r.mouthLowerDownRight = s(current.mouthLowerDownRight, previous.mouthLowerDownRight)
        r.mouthUpperUpLeft = s(current.mouthUpperUpLeft, previous.mouthUpperUpLeft)
        r.mouthUpperUpRight = s(current.mouthUpperUpRight, previous.mouthUpperUpRight)
        r.mouthPressLeft = s(current.mouthPressLeft, previous.mouthPressLeft)
        r.mouthPressRight = s(current.mouthPressRight, previous.mouthPressRight)
        r.mouthDimpleLeft = s(current.mouthDimpleLeft, previous.mouthDimpleLeft)
        r.mouthDimpleRight = s(current.mouthDimpleRight, previous.mouthDimpleRight)
        r.mouthShrugLower = s(current.mouthShrugLower, previous.mouthShrugLower)
        r.mouthShrugUpper = s(current.mouthShrugUpper, previous.mouthShrugUpper)
        r.browDownLeft = s(current.browDownLeft, previous.browDownLeft)
        r.browDownRight = s(current.browDownRight, previous.browDownRight)
        r.browInnerUp = s(current.browInnerUp, previous.browInnerUp)
        r.browOuterUpLeft = s(current.browOuterUpLeft, previous.browOuterUpLeft)
        r.browOuterUpRight = s(current.browOuterUpRight, previous.browOuterUpRight)
        r.cheekPuff = s(current.cheekPuff, previous.cheekPuff)
        r.cheekSquintLeft = s(current.cheekSquintLeft, previous.cheekSquintLeft)
        r.cheekSquintRight = s(current.cheekSquintRight, previous.cheekSquintRight)
        r.eyeBlinkLeft = s(current.eyeBlinkLeft, previous.eyeBlinkLeft)
        r.eyeBlinkRight = s(current.eyeBlinkRight, previous.eyeBlinkRight)
        r.noseSneerLeft = s(current.noseSneerLeft, previous.noseSneerLeft)
        r.noseSneerRight = s(current.noseSneerRight, previous.noseSneerRight)
        r.eyeSquintLeft = s(current.eyeSquintLeft, previous.eyeSquintLeft)
        r.eyeSquintRight = s(current.eyeSquintRight, previous.eyeSquintRight)
        r.eyeWideLeft = s(current.eyeWideLeft, previous.eyeWideLeft)
        r.eyeWideRight = s(current.eyeWideRight, previous.eyeWideRight)
        return r
    }
}
