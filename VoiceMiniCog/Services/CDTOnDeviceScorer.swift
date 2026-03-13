//
//  CDTOnDeviceScorer.swift
//  VoiceMiniCog
//
//  On-device Clock Drawing Test scoring using CoreML
//

import Foundation
import CoreML
import Vision
#if canImport(UIKit)
import UIKit
#endif

/// Result from on-device CDT scoring
struct CDTOnDeviceResult {
    let aiClass: Int  // 0, 1, or 2
    let shulmanRange: String  // "0-1", "2-3", "4-5"
    let severity: String  // "Severe", "Moderate", "Normal/Mild"
    let confidence: Double
    let minicogScore: Int  // 0 or 2 for Mini-Cog scoring
    let probabilities: (severe: Double, moderate: Double, normal: Double)

    var interpretation: String {
        switch aiClass {
        case 0: return "Clock drawing shows significant impairment - Shulman score 0-1"
        case 1: return "Clock drawing shows moderate impairment - Shulman score 2-3"
        case 2: return "Clock drawing is normal or shows mild impairment - Shulman score 4-5"
        default: return "Unable to interpret"
        }
    }

    var clinicalAction: String {
        switch aiClass {
        case 0: return "Recommend comprehensive cognitive evaluation"
        case 1: return "Consider further cognitive assessment"
        case 2: return "No immediate cognitive concerns from clock drawing"
        default: return "Review with clinician"
        }
    }
}

enum CDTScorerError: Error, LocalizedError {
    case modelNotFound
    case preprocessingFailed
    case predictionFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "CDTScorer model not found in app bundle"
        case .preprocessingFailed:
            return "Failed to preprocess image for model"
        case .predictionFailed(let reason):
            return "Prediction failed: \(reason)"
        case .invalidOutput:
            return "Model produced invalid output"
        }
    }
}

class CDTOnDeviceScorer {
    static let shared = CDTOnDeviceScorer()

    private var model: MLModel?
    private var visionModel: VNCoreMLModel?

    private init() {
        loadModel()
    }

    private func loadModel() {
        do {
            // Try to load the compiled model
            guard let modelURL = Bundle.main.url(forResource: "CDTScorer", withExtension: "mlmodelc") else {
                // If not compiled, try to compile from mlpackage
                if let packageURL = Bundle.main.url(forResource: "CDTScorer", withExtension: "mlpackage") {
                    let compiledURL = try MLModel.compileModel(at: packageURL)
                    model = try MLModel(contentsOf: compiledURL)
                    visionModel = try VNCoreMLModel(for: model!)
                    print("[CDT] Model loaded from mlpackage and compiled")
                    return
                }
                print("[CDT] WARNING: CDTScorer model not found in bundle")
                return
            }

            model = try MLModel(contentsOf: modelURL)
            visionModel = try VNCoreMLModel(for: model!)
            print("[CDT] Model loaded successfully")

        } catch {
            print("[CDT] Failed to load model: \(error)")
        }
    }

    func scoreClockDrawing(image: UIImage) async throws -> CDTOnDeviceResult {
        guard let visionModel = visionModel else {
            throw CDTScorerError.modelNotFound
        }

        guard let cgImage = image.cgImage else {
            throw CDTScorerError.preprocessingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: visionModel) { request, error in
                if let error = error {
                    continuation.resume(throwing: CDTScorerError.predictionFailed(error.localizedDescription))
                    return
                }

                guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = results.first?.featureValue.multiArrayValue else {
                    continuation.resume(throwing: CDTScorerError.invalidOutput)
                    return
                }

                // Extract probabilities from multiarray [1, 3]
                let severe = Double(truncating: multiArray[0])
                let moderate = Double(truncating: multiArray[1])
                let normal = Double(truncating: multiArray[2])

                // Find the predicted class
                let probabilities = [severe, moderate, normal]
                let aiClass = probabilities.enumerated().max(by: { $0.element < $1.element })?.offset ?? 1
                let confidence = probabilities[aiClass]

                // Map class to Shulman scale
                let shulmanRange: String
                let severity: String
                let minicogScore: Int

                switch aiClass {
                case 0:
                    shulmanRange = "0-1"
                    severity = "Severe"
                    minicogScore = 0
                case 1:
                    shulmanRange = "2-3"
                    severity = "Moderate"
                    minicogScore = 0
                case 2:
                    shulmanRange = "4-5"
                    severity = "Normal/Mild"
                    minicogScore = 2
                default:
                    shulmanRange = "2-3"
                    severity = "Moderate"
                    minicogScore = 0
                }

                let result = CDTOnDeviceResult(
                    aiClass: aiClass,
                    shulmanRange: shulmanRange,
                    severity: severity,
                    confidence: confidence,
                    minicogScore: minicogScore,
                    probabilities: (severe: severe, moderate: moderate, normal: normal)
                )

                continuation.resume(returning: result)
            }

            // Configure for image input
            request.imageCropAndScaleOption = .scaleFill

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: CDTScorerError.predictionFailed(error.localizedDescription))
            }
        }
    }

    /// Check if model is ready for inference
    var isReady: Bool {
        return model != nil && visionModel != nil
    }
}
