//
//  APIClient.swift
//  VoiceMiniCog
//
//  Handles API communication with backend
//

import Foundation
import os.log
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Server Configuration

/// Centralized server configuration.
/// Set `ServerConfig.baseURL` at app launch (e.g. from a plist, environment variable,
/// or settings bundle) instead of hardcoding an IP address.
struct ServerConfig {
    /// Base URL for the backend API.
    /// **Must** use HTTPS in production builds.
    /// Example: "https://api.example.com"
    static var baseURL: String = {
        // In a real deployment, load from Info.plist, xcconfig, or a settings bundle.
        // The placeholder below will trigger a runtime warning so it is not silently used.
        #if DEBUG
        return "http://localhost:5001"
        #else
        return "https://CONFIGURE_YOUR_SERVER_URL"
        #endif
    }()

    /// Optional authentication token for API requests.
    /// Set this after user login or from secure storage (Keychain).
    static var authToken: String?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceMiniCog", category: "ServerConfig")

    /// Validate the current configuration. Call at app launch.
    static func validate() {
        if baseURL.contains("CONFIGURE_YOUR_SERVER_URL") {
            logger.error("Server base URL has not been configured. Set ServerConfig.baseURL before making API calls.")
        }
        if baseURL.hasPrefix("http://") {
            #if !DEBUG
            logger.error("Insecure HTTP is not allowed in production. Use HTTPS.")
            #else
            logger.warning("Using insecure HTTP — acceptable only during local development.")
            #endif
        }
    }
}

// MARK: - CDT Scoring Response

/// Response from the CDT scoring API
struct CDTScoringResponse: Codable {
    let success: Bool?
    let ai_class: Int  // 0, 1, or 2
    let shulman_range: String  // "0-1", "2-3", "4-5"
    let severity: String  // "Severe", "Moderate", "Normal/Mild"
    let confidence: Double
    let minicog_score: Int?  // 0 or 2 for Mini-Cog scoring
    let interpretation: String
    let clinical_action: String
    let probabilities: CDTProbabilities
}

struct CDTProbabilities: Codable {
    let severe_0_1: Double
    let moderate_2_3: Double
    let normal_4_5: Double
}

class APIClient {
    /// Use `ServerConfig.baseURL` instead of a hardcoded address.
    static var baseURL: String {
        ServerConfig.baseURL
    }

    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceMiniCog", category: "APIClient")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    /// Build a URLRequest with common headers (Content-Type, auth token).
    private func authenticatedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token = ServerConfig.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Next Step API

    func getNextStep(
        phase: Phase,
        transcript: String,
        partialScores: PartialScores
    ) async throws -> NextStepResponse {
        guard let url = URL(string: "\(APIClient.baseURL)/voice-minicog/next-step") else {
            throw APIError.invalidResponse
        }

        var request = authenticatedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = NextStepRequest(
            phase: phase.rawValue,
            transcript: transcript,
            partialScores: partialScores
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(NextStepResponse.self, from: data)
    }

    // MARK: - Clock Analysis API

    func analyzeClock(image: UIImage) async throws -> ClockAnalysisResponse {
        guard let url = URL(string: "\(APIClient.baseURL)/clock/analyze") else {
            throw APIError.invalidResponse
        }

        var request = authenticatedRequest(url: url, method: "POST")

        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add image data
        if let imageData = image.pngData() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"clock.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(ClockAnalysisResponse.self, from: data)
    }

    // MARK: - CDT Scoring API

    func scoreClockDrawing(image: UIImage) async throws -> CDTScoringResponse {
        guard let url = URL(string: "\(APIClient.baseURL)/predict-shulman-base64") else {
            throw APIError.invalidResponse
        }

        var request = authenticatedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Convert image to base64
        guard let pngData = image.pngData() else {
            throw APIError.encodingError
        }
        let base64String = pngData.base64EncodedString()

        let body = ["image": base64String]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }

        return try decoder.decode(CDTScoringResponse.self, from: data)
    }
}

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case encodingError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .encodingError:
            return "Failed to encode request"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}
