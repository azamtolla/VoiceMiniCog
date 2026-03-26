//
//  APIClient.swift
//  VoiceMiniCog
//
//  Handles API communication with backend
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
    // Your Mac's IP for iPad to connect (update if IP changes)
    static let baseURL = "http://192.168.1.169:5001"

    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)

        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    // MARK: - Next Step API

    func getNextStep(
        phase: Phase,
        transcript: String,
        partialScores: PartialScores
    ) async throws -> NextStepResponse {
        let url = URL(string: "\(APIClient.baseURL)/voice-minicog/next-step")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
        let url = URL(string: "\(APIClient.baseURL)/clock/analyze")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

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
        let url = URL(string: "\(APIClient.baseURL)/predict-shulman-base64")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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

    // MARK: - Tavus Conversation API (via backend proxy)

    static let createConversationPath = "/api/tavus/conversation"

    func createTavusConversation(replicaId: String, personaId: String) async throws -> TavusConversationSession {
        let url = URL(string: "\(APIClient.baseURL)\(APIClient.createConversationPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        let body = TavusConversationCreateRequest(replica_id: replicaId, persona_id: personaId)
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        return try decoder.decode(TavusConversationSession.self, from: data)
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
