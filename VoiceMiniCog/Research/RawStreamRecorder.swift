//
//  RawStreamRecorder.swift
//  VoiceMiniCog
//
//  MERIDIAN-1 Section 6.1 raw stream recorder (research-build only).
//
//  This class writes the raw kinematic stream that the whole study is
//  built to measure. Because the app IS the measuring instrument, every
//  data-loss or provenance gap here corrupts the primary ICC. The design
//  below encodes the fixes from the 2026-07-29 multi-agent audit.
//
//  Buffering policy: accumulate touch events in-memory per stroke, flush
//  to JSON Lines on pen-up. Flush is also forced on task-end and, as a
//  safety valve, every `partialFlushThreshold` samples so a mid-stroke
//  termination of a continuous task (worst case: the 90 s spiral) cannot
//  lose the whole task. Rationale: at 240 Hz a 60-second task generates
//  ~14,400 events; write-per-event would introduce I/O contention that
//  degrades the jerk and velocity-CoV features MERIDIAN-1 measures.
//
//  Durability: flushBuffer() batches into one Data blob and uses the
//  THROWING write(contentsOf:) — the deprecated non-throwing write(_:)
//  traps with an uncatchable NSException on I/O failure (disk full,
//  closed handle) and would crash the app mid-visit. Encode failures are
//  counted (droppedSampleCount) and flip captureFailed rather than being
//  silently swallowed, so a punctured stream is flagged, not transferred
//  as if complete (SAP 4.5 session_technical_failure).
//
//  Provenance: beginTask() writes a per-run manifest sidecar BEFORE the
//  first sample (device model, screen scale, points-per-mm calibration,
//  app version, build SHA, task-start wall clock + monotonic origin).
//  This is the artifact that answers the 510(k) DHF question "is the
//  captured data the data your engine processed" (Execution Checklist
//  Phase 2). endTask() writes a SHA-256 sidecar for transfer integrity.
//
//  Filenames carry a wall-clock timestamp component and beginTask refuses
//  to overwrite an existing file, so a protocol-sanctioned task repeat
//  (Checklist Phase 5 deviation log) cannot silently truncate a prior
//  capture via FileManager.createFile.
//
//  Wipe semantics: wipeConfirmedTransfers(_:) deletes ONLY a caller-
//  supplied set of files the operator has verified landed on secure
//  storage, and refuses to run if any un-confirmed file is present — so a
//  single tap can never collaterally destroy another participant's
//  un-transferred data (Section 8.2).
//
//  Storage: .documentDirectory (not .tmp) because files must survive
//  until the transfer window closes; the directory is excluded from
//  iCloud/iTunes backup so raw kinematics never leave the device except
//  through the deliberate transfer path.
//
//  Threading: the module defaults to MainActor isolation
//  (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor); UITouch events and
//  SwiftUI both deliver on the main actor, so no internal locking.
//

#if DEBUG || RESEARCH
import Foundation
import UIKit
import CryptoKit

// MARK: - Errors

/// Surfaced to the examiner UI; a research capture never fails silently.
enum RecorderError: Error, LocalizedError {
    case noActiveStudy
    case invalidParticipantID(String)
    case fileCollision(URL)
    case createFailed(URL)
    case unverifiedFilePresent(URL)
    case wipeIncomplete([URL])

    var errorDescription: String? {
        switch self {
        case .noActiveStudy:
            return "Research Mode is not active with a validated participant ID."
        case .invalidParticipantID(let id):
            return "Participant ID \"\(id)\" is not a valid 5-character study code."
        case .fileCollision(let url):
            return "A capture already exists at \(url.lastPathComponent). Refusing to overwrite."
        case .createFailed(let url):
            return "Could not create capture file \(url.lastPathComponent)."
        case .unverifiedFilePresent(let url):
            return "Refusing to wipe: \(url.lastPathComponent) has not been confirmed as transferred."
        case .wipeIncomplete(let urls):
            return "Wipe incomplete; \(urls.count) file(s) could not be removed."
        }
    }
}

// MARK: - Build & device provenance

/// Immutable build identity for the run manifest. `commitSHA` is intended
/// to be injected at build time (Info.plist key `GitCommitSHA`, set by a
/// build phase); until that phase exists it reads "UNSET-see-DHF" so the
/// gap is visible in every manifest rather than fabricated.
enum BuildInfo {
    static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }
    static var commitSHA: String {
        (Bundle.main.infoDictionary?["GitCommitSHA"] as? String) ?? "UNSET-see-DHF"
    }
}

/// Points→millimetre calibration. UIKit reports coordinates in points;
/// ICC/transfer-functions require millimetres. mm = points / pointsPerMM.
/// pointsPerMM = (physical ppi / nativeScale) / 25.4. iPad Pro 11"/13" (M4)
/// and the 12.9" (M1/M2) are all 264 ppi at 2× → 132 pt/in → 5.1969 pt/mm.
/// An unknown model records a documented fallback so capture is never lost
/// to a missing table entry — the `calibrationSource` field flags it.
enum DeviceCalibration {
    static let fallbackPointsPerMM = 132.0 / 25.4  // 264 ppi class

    private static let table: [String: Double] = [
        "iPad16,3": 132.0 / 25.4, "iPad16,4": 132.0 / 25.4,  // iPad Pro 11" (M4)
        "iPad16,5": 132.0 / 25.4, "iPad16,6": 132.0 / 25.4,  // iPad Pro 13" (M4)
        "iPad14,5": 132.0 / 25.4, "iPad14,6": 132.0 / 25.4,  // iPad Pro 12.9" 6th gen (M2)
        "iPad13,8": 132.0 / 25.4, "iPad13,9": 132.0 / 25.4,
        "iPad13,10": 132.0 / 25.4, "iPad13,11": 132.0 / 25.4, // iPad Pro 12.9" 5th gen (M1)
    ]

    static func pointsPerMM(for model: String) -> (value: Double, source: String) {
        if let v = table[model] { return (v, "table") }
        return (fallbackPointsPerMM, "fallback")
    }

    /// Hardware model identifier, e.g. "iPad16,6". On the simulator this
    /// returns the host arch (e.g. "arm64") — recorded verbatim, and the
    /// manifest's calibrationSource will read "fallback" there.
    static var modelIdentifier: String {
        var sys = utsname()
        uname(&sys)
        let bytes = withUnsafeBytes(of: &sys.machine) { raw -> [UInt8] in
            raw.prefix { $0 != 0 }.map { $0 }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Per-run provenance record, written once at beginTask() before any sample.
struct RunManifest: Encodable {
    let schemaVersion = 2
    let participantID: String
    let siteStudyID: String?
    let platform: String
    let task: String
    let session: Int
    let appVersion: String
    let buildSHA: String
    let deviceModel: String
    let osVersion: String
    let screenNativeScale: Double
    let pointsPerMillimeter: Double
    let calibrationSource: String            // "table" | "fallback"
    let sampleRateHintHz: Int
    let taskStartWallClockISO8601: String
    let taskStartMonotonicMs: Double         // == stream t-origin
    let azimuthConvention: String
    let pressureNormalization: String
}

// MARK: - Recorder

final class RawStreamRecorder {

    /// One captured sample. `t` is milliseconds from task start (the
    /// beginTask monotonic origin), stamped from each sample's own
    /// `UITouch.timestamp`. `x`/`y` are UIKit points (convert to mm with
    /// the manifest's pointsPerMillimeter). Raw force is retained
    /// alongside the normalized value (Section 6.1). `phase` and `stroke`
    /// make ink/air time, latency, and closure-gap features computable.
    struct TouchSample: Encodable {
        let t: Double        // ms from task start, per-sample hardware time
        let x: Float         // UIKit points (mm = x / pointsPerMillimeter)
        let y: Float
        let p: Float         // normalized 0–1 (0 if no force sensor)
        let pRaw: Float      // raw device force
        let pMax: Float      // maximumPossibleForce at capture (0 ⇒ no sensor)
        let alt: Float       // altitude, radians
        let az: Float        // azimuth, radians (UIKit view frame, y-down)
        let type: String     // stylus | direct | predicted | other
        let phase: String    // down | move | up
        var stroke: Int = 0  // 0-based stroke index within the task
    }

    // MARK: State
    private var strokeBuffer: [TouchSample] = []
    private var fileHandle: FileHandle?
    private var currentFileURL: URL?
    private var currentBase: String?
    private var currentStrokeIndex: Int = -1

    /// Monotonic milliseconds marking task start; also the stream t-origin.
    private(set) var taskStartMonotonicMs: Double = 0
    /// Samples lost to encode failure this task (surfaced to the examiner).
    private(set) var droppedSampleCount: Int = 0
    /// True if any encode/write fault occurred — the session must be
    /// marked session_technical_failure (SAP 4.5), not transferred as valid.
    private(set) var captureFailed: Bool = false

    private let partialFlushThreshold = 512
    private let newline = Data([0x0A])
    private let encoder = JSONEncoder()   // default .throw on non-finite → caught + counted

    // MARK: Session lifecycle

    /// Open a capture file for one (participant, platform, task, session).
    /// The participant ID is taken from the validated Research-Mode session,
    /// never from an arbitrary caller string, so the gated ID and the
    /// filename cannot diverge.
    func beginTask(platform: String, task: String, session: Int) throws {
        // Close any still-open task first (flush + close), so a missed
        // endTask() cannot leak a handle or drop its final stroke.
        if fileHandle != nil { try? endTask() }

        guard ResearchModeSettings.shared.isActive,
              let participantID = ResearchModeSettings.shared.activeStudyID else {
            throw RecorderError.noActiveStudy
        }
        // Participant ID is a path component and the de-identification key
        // (Protocol 8.1/8.2): 5 chars, no confusable 0/O/1/I/L (Checklist).
        guard participantID.range(of: "^[A-HJ-NP-Z2-9]{5}$", options: .regularExpression) != nil else {
            throw RecorderError.invalidParticipantID(participantID)
        }

        let dir = try Self.streamDirectory()
        let stamp = Int(Date().timeIntervalSince1970)
        let base = "\(participantID)_\(platform)_\(task)_\(session)_\(stamp)"
        let url = dir.appendingPathComponent(base + ".jsonl")

        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw RecorderError.fileCollision(url)
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw RecorderError.createFailed(url)
        }

        fileHandle = try FileHandle(forWritingTo: url)
        currentFileURL = url
        currentBase = base
        currentStrokeIndex = -1
        droppedSampleCount = 0
        captureFailed = false
        strokeBuffer.removeAll()

        // The stream t-origin. touch.timestamp and DispatchTime.uptime share
        // the mach monotonic base, so per-sample times reference this origin
        // consistently — and zeroing at task start (not first pen-down)
        // preserves pre_first_hand_latency (primary feature 9).
        taskStartMonotonicMs = Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000

        try writeManifest(base: base, dir: dir, participantID: participantID,
                          platform: platform, task: task, session: session)
    }

    /// Flush, checksum, and close the current task.
    func endTask() throws {
        try flushBuffer()
        if let url = currentFileURL, let base = currentBase,
           let sha = try? Self.sha256(of: url) {
            // Integrity sidecar for the "checksum everything" transfer step.
            let shaURL = url.deletingLastPathComponent().appendingPathComponent(base + ".sha256")
            try? "\(sha)  \(url.lastPathComponent)\n".data(using: .utf8)?.write(to: shaURL)
        }
        try? fileHandle?.close()
        fileHandle = nil
        currentFileURL = nil
        currentBase = nil
    }

    // MARK: Touch intake

    /// Append one sample. The recorder owns stroke indexing (single source
    /// of truth across view remounts): a "down" phase opens a new stroke.
    func recordSample(_ sample: TouchSample) {
        var s = sample
        if s.phase == "down" { currentStrokeIndex += 1 }
        s.stroke = max(0, currentStrokeIndex)
        strokeBuffer.append(s)
        if strokeBuffer.count >= partialFlushThreshold {
            // Safety-valve flush mid-stroke; errors flip captureFailed but
            // never crash the capture.
            do { try flushBuffer() } catch { captureFailed = true }
        }
    }

    /// Call on every UITouch phase .ended / .cancelled.
    func penUp() {
        do { try flushBuffer() } catch { captureFailed = true }
    }

    // MARK: Transfer-confirm wipe (Section 8.2)

    /// Delete ONLY the files the operator has verified transferred to
    /// secure storage. Refuses to run if any un-confirmed file is present,
    /// so another participant's un-transferred data can never be
    /// collaterally wiped. Deactivates Research Mode only once the stream
    /// directory is fully empty.
    func wipeConfirmedTransfers(_ confirmed: Set<URL>) throws {
        try? endTask()
        let dir = try Self.streamDirectory()
        let present = Set(try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil))

        let unconfirmed = present.subtracting(confirmed)
        if let stray = unconfirmed.first {
            throw RecorderError.unverifiedFilePresent(stray)   // abort; delete nothing
        }

        var failures: [URL] = []
        for file in present {
            do { try FileManager.default.removeItem(at: file) }
            catch { failures.append(file) }
        }
        let remaining = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        if remaining.isEmpty {
            ResearchModeSettings.shared.deactivate()
        } else {
            throw RecorderError.wipeIncomplete(failures.isEmpty ? remaining : failures)
        }
    }

    /// All files currently in the stream directory — used by the launcher
    /// to build the confirmed-transfer set after the operator verifies the
    /// copy landed on secure storage.
    func streamFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: Self.streamDirectory(), includingPropertiesForKeys: nil)
    }

    // MARK: Private

    private func flushBuffer() throws {
        guard !strokeBuffer.isEmpty else { return }
        guard let handle = fileHandle else { strokeBuffer.removeAll(); return }

        var data = Data()
        for sample in strokeBuffer {
            do {
                data.append(try encoder.encode(sample))
                data.append(newline)
            } catch {
                droppedSampleCount += 1
                captureFailed = true
            }
        }
        // Throwing write; buffer is cleared only after a durable write so a
        // transient failure does not silently discard unsaved samples.
        try handle.write(contentsOf: data)
        strokeBuffer.removeAll()
    }

    private func writeManifest(base: String, dir: URL, participantID: String,
                               platform: String, task: String, session: Int) throws {
        let model = DeviceCalibration.modelIdentifier
        let cal = DeviceCalibration.pointsPerMM(for: model)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let manifest = RunManifest(
            participantID: participantID,
            siteStudyID: ResearchModeSettings.shared.siteStudyID,
            platform: platform,
            task: task,
            session: session,
            appVersion: BuildInfo.appVersion,
            buildSHA: BuildInfo.commitSHA,
            deviceModel: model,
            osVersion: UIDevice.current.systemVersion,
            screenNativeScale: Double(UIScreen.main.nativeScale),
            pointsPerMillimeter: cal.value,
            calibrationSource: cal.source,
            sampleRateHintHz: 240,
            taskStartWallClockISO8601: iso.string(from: Date()),
            taskStartMonotonicMs: taskStartMonotonicMs,
            azimuthConvention: "UIKit_view_x_axis_y_down",
            pressureNormalization: "force_over_maximumPossibleForce"
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestURL = dir.appendingPathComponent(base + ".manifest.json")
        try enc.encode(manifest).write(to: manifestURL)
    }

    private static func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func streamDirectory() throws -> URL {
        let base = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0]
        var dir = base.appendingPathComponent("MERIDIAN1_streams", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        // Raw kinematics must not sync to iCloud/iTunes backup; the only
        // path off-device is the deliberate transfer step.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }
}
#endif
