//
//  ClockDrawingCapture.swift
//  VoiceMiniCog
//
//  Captures the patient's live clock drawing — both the final image and a
//  sparse replay of strokes — for the clinician's report.
//
//  CLINICAL RATIONALE:
//    Clock drawing is a LIVE process test, not just a final-product test.
//    Hesitations, corrections, tremor, and decision sequence are diagnostic.
//    O'Caoimh QMCI scores the final product (/15), but clinician interpretation
//    benefits from seeing the process. We store:
//      - Final raster image (for QMCI scoring + PDF)
//      - Ordered stroke list (timestamped points) for a replay widget
//      - Total draw duration
//      - Number of pen-lifts (proxy for hesitation)
//

import Combine
import CoreGraphics
import Foundation

public struct ClockStroke: Codable, Identifiable, Equatable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let points: [StrokePoint]

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, points: [StrokePoint]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.points = points
    }
}

public struct StrokePoint: Codable, Equatable {
    public let x: Double
    public let y: Double
    public let t: TimeInterval   // seconds since stroke start

    public init(x: Double, y: Double, t: TimeInterval) {
        self.x = x
        self.y = y
        self.t = t
    }
}

public struct ClockDrawingCapture: Codable, Equatable {

    public let startedAt: Date
    public var endedAt: Date?
    public var strokes: [ClockStroke]
    public var finalImageData: Data?      // PNG raster for PDF / QMCI scorer

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        self.endedAt = nil
        self.strokes = []
        self.finalImageData = nil
    }

    public var durationSeconds: TimeInterval {
        guard let endedAt else { return 0 }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// Number of pen-lifts — proxy for hesitation. High values for MCI/early
    /// dementia patients correlate with planning difficulty.
    public var penLiftCount: Int {
        // Stroke count minus 1 equals pen-lifts between strokes.
        max(strokes.count - 1, 0)
    }

    /// Total strokes drawn.
    public var strokeCount: Int { strokes.count }

    // MARK: - Recording

    public mutating func appendStroke(_ stroke: ClockStroke) {
        strokes.append(stroke)
    }

    public mutating func finalize(image pngData: Data?) {
        self.finalImageData = pngData
        self.endedAt = Date()
    }

    // MARK: - Serialization

    public func jsonData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(from data: Data) -> ClockDrawingCapture? {
        try? JSONDecoder().decode(ClockDrawingCapture.self, from: data)
    }
}

// MARK: - Live recorder (reference-type for phase view)

@MainActor
public final class ClockDrawingRecorder: ObservableObject {

    @Published public private(set) var capture: ClockDrawingCapture

    private var currentStrokeStart: Date?
    private var currentStrokePoints: [StrokePoint] = []

    public init() {
        self.capture = ClockDrawingCapture()
    }

    public func beginStroke() {
        currentStrokeStart = Date()
        currentStrokePoints.removeAll()
    }

    public func addPoint(_ cgPoint: CGPoint) {
        guard let start = currentStrokeStart else { return }
        let t = Date().timeIntervalSince(start)
        currentStrokePoints.append(StrokePoint(x: Double(cgPoint.x), y: Double(cgPoint.y), t: t))
    }

    public func endStroke() {
        guard let start = currentStrokeStart, !currentStrokePoints.isEmpty else {
            currentStrokeStart = nil
            return
        }
        capture.appendStroke(ClockStroke(
            startedAt: start,
            endedAt: Date(),
            points: currentStrokePoints
        ))
        currentStrokeStart = nil
        currentStrokePoints.removeAll()
    }

    public func finalize(pngData: Data?) {
        capture.finalize(image: pngData)
    }
}
