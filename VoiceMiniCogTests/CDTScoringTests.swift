//
//  CDTScoringTests.swift
//  VoiceMiniCogTests
//
//  Tests for CDTOnDeviceScorer: class mapping, softmax normalization,
//  label spec resolution, and end-to-end scoring alignment.
//
//  Xcode setup:
//  1. Add this file to the VoiceMiniCogTests target
//  2. Add CDTScorer.mlpackage to the test target's "Copy Bundle Resources"
//  3. Add cdt_label_spec.json to the test target's "Copy Bundle Resources"
//  4. For image-based tests, add test clock images to a TestClocks folder
//     in the test target's bundle
//

import XCTest
import CoreML
@testable import VoiceMiniCog

// MARK: - Helper: Create MLMultiArray from probabilities

/// Creates a [1, 3] MLMultiArray matching the model's output shape.
/// Deterministic — no randomness.
private func makeMultiArray(_ values: [Double]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, 3], dataType: .float32)
    for (i, value) in values.enumerated() {
        array[i] = NSNumber(value: value)
    }
    return array
}

// MARK: - Unit Tests: Class Index Mapping

class CDTClassMappingTests: XCTestCase {

    /// Test: Index 0 → Severe (Shulman 0-1) → Mini-Cog 0
    func testClassZeroMapsSevere() throws {
        // Probabilities: class 0 is dominant
        let multiArray = try makeMultiArray([0.85, 0.10, 0.05])
        let result = try CDTOnDeviceScorer.interpretOutput(multiArray: multiArray)

        XCTAssertEqual(result.aiClass, 0, "Class 0 should be Severe")
        XCTAssertEqual(result.shulmanRange, "0-1")
        XCTAssertEqual(result.severity, "Severe")
        XCTAssertEqual(result.minicogScore, 0, "Severe → Mini-Cog 0")
        XCTAssertEqual(result.confidence, 0.85, accuracy: 1e-6)
    }

    /// Test: Index 1 → Moderate (Shulman 2-3) → Mini-Cog 0
    func testClassOneMapModerate() throws {
        let multiArray = try makeMultiArray([0.10, 0.80, 0.10])
        let result = try CDTOnDeviceScorer.interpretOutput(multiArray: multiArray)

        XCTAssertEqual(result.aiClass, 1, "Class 1 should be Moderate")
        XCTAssertEqual(result.shulmanRange, "2-3")
        XCTAssertEqual(result.severity, "Moderate")
        XCTAssertEqual(result.minicogScore, 0, "Moderate → Mini-Cog 0")
        XCTAssertEqual(result.confidence, 0.80, accuracy: 1e-6)
    }

    /// Test: Index 2 → Normal/Mild (Shulman 4-5) → Mini-Cog 2
    func testClassTwoMapsNormal() throws {
        let multiArray = try makeMultiArray([0.05, 0.10, 0.85])
        let result = try CDTOnDeviceScorer.interpretOutput(multiArray: multiArray)

        XCTAssertEqual(result.aiClass, 2, "Class 2 should be Normal/Mild")
        XCTAssertEqual(result.shulmanRange, "4-5")
        XCTAssertEqual(result.severity, "Normal/Mild")
        XCTAssertEqual(result.minicogScore, 2, "Normal → Mini-Cog 2")
        XCTAssertEqual(result.confidence, 0.85, accuracy: 1e-6)
    }

    /// Test: Mini-Cog score is 0 for both Severe and Moderate, 2 only for Normal
    func testMiniCogScoreBinaryMapping() throws {
        // Severe → 0
        let severe = try CDTOnDeviceScorer.interpretOutput(
            multiArray: try makeMultiArray([0.7, 0.2, 0.1])
        )
        XCTAssertEqual(severe.minicogScore, 0)

        // Moderate → 0
        let moderate = try CDTOnDeviceScorer.interpretOutput(
            multiArray: try makeMultiArray([0.1, 0.7, 0.2])
        )
        XCTAssertEqual(moderate.minicogScore, 0)

        // Normal → 2
        let normal = try CDTOnDeviceScorer.interpretOutput(
            multiArray: try makeMultiArray([0.1, 0.2, 0.7])
        )
        XCTAssertEqual(normal.minicogScore, 2)
    }

    /// Test: Probabilities tuple always maps to named fields correctly
    func testProbabilitiesNamedFields() throws {
        let multiArray = try makeMultiArray([0.25, 0.35, 0.40])
        let result = try CDTOnDeviceScorer.interpretOutput(multiArray: multiArray)

        XCTAssertEqual(result.probabilities.severe, 0.25, accuracy: 1e-6,
                       "Index 0 → .severe")
        XCTAssertEqual(result.probabilities.moderate, 0.35, accuracy: 1e-6,
                       "Index 1 → .moderate")
        XCTAssertEqual(result.probabilities.normal, 0.40, accuracy: 1e-6,
                       "Index 2 → .normal")
    }

    /// Test: Argmax breaks ties deterministically (first highest wins)
    func testTieBreaking() throws {
        // Indices 0 and 1 tied at 0.4
        let multiArray = try makeMultiArray([0.4, 0.4, 0.2])
        let result = try CDTOnDeviceScorer.interpretOutput(multiArray: multiArray)

        // Argmax should pick index 0 (first occurrence)
        XCTAssertEqual(result.aiClass, 0,
                       "Tie should be broken by first-highest (deterministic)")
    }
}

// MARK: - Unit Tests: Softmax Normalization

class CDTSoftmaxTests: XCTestCase {

    /// Test: Already-normalized probabilities pass through unchanged
    func testPassthroughForNormalizedValues() {
        let input = [0.2, 0.3, 0.5]
        let output = CDTOnDeviceScorer.softmaxNormalize(input)

        for (i, val) in output.enumerated() {
            XCTAssertEqual(val, input[i], accuracy: 1e-10,
                           "Normalized values should pass through unchanged")
        }
    }

    /// Test: Raw logits get softmax-normalized
    func testSoftmaxAppliedToLogits() {
        // These are raw logits (sum != 1.0)
        let logits = [2.0, 1.0, 0.5]
        let output = CDTOnDeviceScorer.softmaxNormalize(logits)

        // Sum should be ~1.0
        let sum = output.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 1e-10, "Softmax output must sum to 1.0")

        // Order should be preserved
        XCTAssertGreaterThan(output[0], output[1], "Highest logit → highest probability")
        XCTAssertGreaterThan(output[1], output[2])

        // All probabilities should be positive
        for val in output {
            XCTAssertGreaterThan(val, 0.0, "All softmax outputs must be positive")
        }
    }

    /// Test: Large logits don't cause overflow (numerical stability)
    func testNumericalStabilityLargeLogits() {
        let logits = [1000.0, 999.0, 998.0]
        let output = CDTOnDeviceScorer.softmaxNormalize(logits)

        let sum = output.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 1e-6,
                       "Large logits should not cause overflow")
        XCTAssertGreaterThan(output[0], output[1])
        XCTAssertFalse(output.contains(where: { $0.isNaN }),
                       "No NaN values in output")
        XCTAssertFalse(output.contains(where: { $0.isInfinite }),
                       "No Inf values in output")
    }

    /// Test: Negative logits work correctly
    func testNegativeLogits() {
        let logits = [-1.0, -2.0, -0.5]
        let output = CDTOnDeviceScorer.softmaxNormalize(logits)

        let sum = output.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 1e-10)
        // -0.5 is the largest, so index 2 should have highest prob
        XCTAssertGreaterThan(output[2], output[0])
        XCTAssertGreaterThan(output[0], output[1])
    }

    /// Test: Identical logits produce uniform distribution
    func testUniformForIdenticalLogits() {
        let logits = [3.0, 3.0, 3.0]
        let output = CDTOnDeviceScorer.softmaxNormalize(logits)

        for val in output {
            XCTAssertEqual(val, 1.0 / 3.0, accuracy: 1e-10,
                           "Equal logits → uniform distribution")
        }
    }

    /// Test: Determinism — same input always produces same output
    func testDeterminism() {
        let logits = [1.5, 2.3, 0.8]
        let output1 = CDTOnDeviceScorer.softmaxNormalize(logits)
        let output2 = CDTOnDeviceScorer.softmaxNormalize(logits)

        for i in 0..<output1.count {
            XCTAssertEqual(output1[i], output2[i],
                           "Softmax must be deterministic (SaMD requirement)")
        }
    }
}

// MARK: - Unit Tests: Label Spec

class CDTLabelSpecTests: XCTestCase {

    /// Test: Default spec has correct structure
    func testDefaultSpecStructure() {
        let spec = CDTLabelSpec.defaultSpec
        XCTAssertEqual(spec.numClasses, 3)
        XCTAssertEqual(spec.classes.count, 3)
        XCTAssertEqual(spec.classes[0].label, "severe_0_1")
        XCTAssertEqual(spec.classes[1].label, "moderate_2_3")
        XCTAssertEqual(spec.classes[2].label, "normal_4_5")
    }

    /// Test: Default spec indices are 0, 1, 2
    func testDefaultSpecIndices() {
        let spec = CDTLabelSpec.defaultSpec
        let indices = spec.classes.map(\.index)
        XCTAssertEqual(indices, [0, 1, 2])
    }

    /// Test: Default spec Mini-Cog scores match clinical protocol
    func testDefaultSpecMiniCogScores() {
        let spec = CDTLabelSpec.defaultSpec
        XCTAssertEqual(spec.classes[0].minicogScore, 0, "Severe → 0")
        XCTAssertEqual(spec.classes[1].minicogScore, 0, "Moderate → 0")
        XCTAssertEqual(spec.classes[2].minicogScore, 2, "Normal → 2")
    }

    /// Test: JSON decoding round-trip matches default
    func testJSONRoundTrip() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(CDTLabelSpec.defaultSpec)
        let decoded = try JSONDecoder().decode(CDTLabelSpec.self, from: data)

        XCTAssertEqual(decoded.numClasses, 3)
        for (i, cls) in decoded.classes.enumerated() {
            XCTAssertEqual(cls.label, CDTLabelSpec.defaultSpec.classes[i].label)
            XCTAssertEqual(cls.index, CDTLabelSpec.defaultSpec.classes[i].index)
            XCTAssertEqual(cls.minicogScore, CDTLabelSpec.defaultSpec.classes[i].minicogScore)
        }
    }

    /// Test: Custom label spec with reordered indices works correctly
    func testReorderedLabelSpec() throws {
        // Simulate a model that outputs [normal, severe, moderate]
        let reorderedSpec = CDTLabelSpec(
            modelName: "CDTScorer",
            modelVersion: "2.0",
            numClasses: 3,
            classes: [
                CDTClassSpec(index: 0, label: "normal_4_5",
                             shulmanRange: "4-5", severity: "Normal/Mild", minicogScore: 2,
                             interpretation: "Normal", clinicalAction: "None"),
                CDTClassSpec(index: 1, label: "severe_0_1",
                             shulmanRange: "0-1", severity: "Severe", minicogScore: 0,
                             interpretation: "Severe", clinicalAction: "Evaluate"),
                CDTClassSpec(index: 2, label: "moderate_2_3",
                             shulmanRange: "2-3", severity: "Moderate", minicogScore: 0,
                             interpretation: "Moderate", clinicalAction: "Screen"),
            ]
        )

        // Output: [0.8, 0.1, 0.1] → index 0 → "normal_4_5" in this spec
        let multiArray = try makeMultiArray([0.8, 0.1, 0.1])
        let result = try CDTOnDeviceScorer.interpretOutput(
            multiArray: multiArray, labelSpec: reorderedSpec
        )

        XCTAssertEqual(result.severity, "Normal/Mild",
                       "Reordered spec: index 0 should map to Normal")
        XCTAssertEqual(result.minicogScore, 2)
        // The .severe probability should come from index 1 (where severe is)
        XCTAssertEqual(result.probabilities.severe, 0.1, accuracy: 1e-6)
        XCTAssertEqual(result.probabilities.normal, 0.8, accuracy: 1e-6)
    }
}

// MARK: - Integration Tests: Known Clock Images

/// These tests require actual clock drawing images in the test bundle.
/// Add a "TestClocks" folder to VoiceMiniCogTests with:
///   - clock_severe.png   (known Shulman 0-1)
///   - clock_moderate.png (known Shulman 2-3)
///   - clock_normal.png   (known Shulman 4-5)
///
/// Also requires CDTScorer.mlpackage in the test target's Copy Bundle Resources.
class CDTKnownClockTests: XCTestCase {

    private var scorer: CDTOnDeviceScorer?

    override func setUp() {
        super.setUp()
        // Try to load model from test bundle
        let testBundle = Bundle(for: type(of: self))
        guard let modelURL = testBundle.url(forResource: "CDTScorer", withExtension: "mlmodelc")
                ?? testBundle.url(forResource: "CDTScorer", withExtension: "mlpackage") else {
            // Model not in test bundle — skip integration tests
            return
        }

        do {
            let compiledURL: URL
            if modelURL.pathExtension == "mlpackage" {
                compiledURL = try MLModel.compileModel(at: modelURL)
            } else {
                compiledURL = modelURL
            }
            let model = try MLModel(contentsOf: compiledURL)
            scorer = try CDTOnDeviceScorer(model: model)
        } catch {
            XCTFail("Failed to load model for integration tests: \(error)")
        }
    }

    /// Load a test image from the test bundle's TestClocks folder.
    private func loadTestImage(named name: String) -> UIImage? {
        let testBundle = Bundle(for: type(of: self))

        // Try direct resource lookup
        if let url = testBundle.url(forResource: name, withExtension: "png",
                                     subdirectory: "TestClocks") {
            return UIImage(contentsOfFile: url.path)
        }

        // Try without subdirectory
        if let url = testBundle.url(forResource: name, withExtension: "png") {
            return UIImage(contentsOfFile: url.path)
        }

        return nil
    }

    /// Test: Known severe clock → class 0, Shulman 0-1
    func testSevereClock() async throws {
        guard let scorer = scorer else {
            throw XCTSkip("CDTScorer model not available in test bundle")
        }
        guard let image = loadTestImage(named: "clock_severe") else {
            throw XCTSkip("clock_severe.png not found in TestClocks")
        }

        let result = try await scorer.scoreClockDrawing(image: image)

        print("[TEST] Severe clock — class: \(result.aiClass), "
              + "confidence: \(result.confidence), "
              + "probs: [\(result.probabilities.severe), "
              + "\(result.probabilities.moderate), "
              + "\(result.probabilities.normal)]")

        XCTAssertEqual(result.aiClass, 0,
                       "Severe clock should classify as class 0")
        XCTAssertEqual(result.shulmanRange, "0-1")
        XCTAssertEqual(result.minicogScore, 0)
        XCTAssertGreaterThan(result.probabilities.severe,
                             result.probabilities.moderate,
                             "Severe prob should be highest")
        XCTAssertGreaterThan(result.probabilities.severe,
                             result.probabilities.normal)
    }

    /// Test: Known moderate clock → class 1, Shulman 2-3
    func testModerateClock() async throws {
        guard let scorer = scorer else {
            throw XCTSkip("CDTScorer model not available in test bundle")
        }
        guard let image = loadTestImage(named: "clock_moderate") else {
            throw XCTSkip("clock_moderate.png not found in TestClocks")
        }

        let result = try await scorer.scoreClockDrawing(image: image)

        print("[TEST] Moderate clock — class: \(result.aiClass), "
              + "confidence: \(result.confidence), "
              + "probs: [\(result.probabilities.severe), "
              + "\(result.probabilities.moderate), "
              + "\(result.probabilities.normal)]")

        XCTAssertEqual(result.aiClass, 1,
                       "Moderate clock should classify as class 1")
        XCTAssertEqual(result.shulmanRange, "2-3")
        XCTAssertEqual(result.minicogScore, 0)
        XCTAssertGreaterThan(result.probabilities.moderate,
                             result.probabilities.severe,
                             "Moderate prob should be highest")
        XCTAssertGreaterThan(result.probabilities.moderate,
                             result.probabilities.normal)
    }

    /// Test: Known normal clock → class 2, Shulman 4-5
    func testNormalClock() async throws {
        guard let scorer = scorer else {
            throw XCTSkip("CDTScorer model not available in test bundle")
        }
        guard let image = loadTestImage(named: "clock_normal") else {
            throw XCTSkip("clock_normal.png not found in TestClocks")
        }

        let result = try await scorer.scoreClockDrawing(image: image)

        print("[TEST] Normal clock — class: \(result.aiClass), "
              + "confidence: \(result.confidence), "
              + "probs: [\(result.probabilities.severe), "
              + "\(result.probabilities.moderate), "
              + "\(result.probabilities.normal)]")

        XCTAssertEqual(result.aiClass, 2,
                       "Normal clock should classify as class 2")
        XCTAssertEqual(result.shulmanRange, "4-5")
        XCTAssertEqual(result.minicogScore, 2)
        XCTAssertGreaterThan(result.probabilities.normal,
                             result.probabilities.severe,
                             "Normal prob should be highest")
        XCTAssertGreaterThan(result.probabilities.normal,
                             result.probabilities.moderate)
    }

    /// Test: Probability bucket ordering is consistent with API response format
    func testProbabilityOrderMatchesBackend() async throws {
        guard let scorer = scorer else {
            throw XCTSkip("CDTScorer model not available in test bundle")
        }
        guard let image = loadTestImage(named: "clock_normal") else {
            throw XCTSkip("clock_normal.png not found in TestClocks")
        }

        let result = try await scorer.scoreClockDrawing(image: image)

        // Verify probabilities sum to ~1.0 (softmax output)
        let total = result.probabilities.severe
            + result.probabilities.moderate
            + result.probabilities.normal
        XCTAssertEqual(total, 1.0, accuracy: 0.01,
                       "Probabilities must sum to ~1.0")

        // Verify all probabilities are in [0, 1]
        XCTAssertGreaterThanOrEqual(result.probabilities.severe, 0.0)
        XCTAssertLessThanOrEqual(result.probabilities.severe, 1.0)
        XCTAssertGreaterThanOrEqual(result.probabilities.moderate, 0.0)
        XCTAssertLessThanOrEqual(result.probabilities.moderate, 1.0)
        XCTAssertGreaterThanOrEqual(result.probabilities.normal, 0.0)
        XCTAssertLessThanOrEqual(result.probabilities.normal, 1.0)
    }
}

// MARK: - Cross-Validation: On-Device vs Backend

/// Python companion script for generating expected outputs:
///
///   python3 cross_validate_cdt.py clock_severe.png clock_moderate.png clock_normal.png
///
/// That script outputs JSON with backend predictions for each image.
/// Copy the expected values into the constants below.
///
/// These tests verify that the on-device model produces the same argmax class
/// as the backend for each test image. Probability values may differ slightly
/// due to preprocessing differences (PIL resize vs Vision scaleFill).
class CDTCrossValidationTests: XCTestCase {

    /// Expected backend results for test images.
    /// Update these after running cross_validate_cdt.py on your RunPod server.
    struct ExpectedBackendResult {
        let imageName: String
        let expectedClass: Int
        let expectedShulmanRange: String
    }

    static let expectedResults: [ExpectedBackendResult] = [
        // Fill these in after running the Python cross-validation script:
        // ExpectedBackendResult(imageName: "clock_severe", expectedClass: 0, expectedShulmanRange: "0-1"),
        // ExpectedBackendResult(imageName: "clock_moderate", expectedClass: 1, expectedShulmanRange: "2-3"),
        // ExpectedBackendResult(imageName: "clock_normal", expectedClass: 2, expectedShulmanRange: "4-5"),
    ]

    func testCrossValidation() async throws {
        guard !Self.expectedResults.isEmpty else {
            throw XCTSkip("No expected backend results configured. "
                          + "Run cross_validate_cdt.py first.")
        }

        let testBundle = Bundle(for: type(of: self))
        guard let modelURL = testBundle.url(forResource: "CDTScorer", withExtension: "mlmodelc")
                ?? testBundle.url(forResource: "CDTScorer", withExtension: "mlpackage") else {
            throw XCTSkip("CDTScorer model not in test bundle")
        }

        let compiledURL: URL
        if modelURL.pathExtension == "mlpackage" {
            compiledURL = try MLModel.compileModel(at: modelURL)
        } else {
            compiledURL = modelURL
        }
        let model = try MLModel(contentsOf: compiledURL)
        let scorer = try CDTOnDeviceScorer(model: model)

        for expected in Self.expectedResults {
            guard let url = testBundle.url(forResource: expected.imageName, withExtension: "png",
                                           subdirectory: "TestClocks"),
                  let image = UIImage(contentsOfFile: url.path) else {
                XCTFail("Test image not found: \(expected.imageName).png")
                continue
            }

            let result = try await scorer.scoreClockDrawing(image: image)

            print("[CROSS-VAL] \(expected.imageName): "
                  + "on-device=\(result.aiClass) backend=\(expected.expectedClass) "
                  + "probs=[\(result.probabilities.severe), "
                  + "\(result.probabilities.moderate), "
                  + "\(result.probabilities.normal)]")

            XCTAssertEqual(result.aiClass, expected.expectedClass,
                           "\(expected.imageName): on-device class \(result.aiClass) "
                           + "!= backend class \(expected.expectedClass)")
            XCTAssertEqual(result.shulmanRange, expected.expectedShulmanRange,
                           "\(expected.imageName): Shulman range mismatch")
        }
    }
}
