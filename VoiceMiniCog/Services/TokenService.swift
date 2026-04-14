//
//  TokenService.swift
//  VoiceMiniCog
//
//  Fetches ephemeral OpenAI Realtime tokens from backend
//  No API keys stored in the iOS app
//

import Foundation
import os.log

// MARK: - Token Response Model

struct RealtimeTokenResponse: Codable {
    let clientSecret: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case clientSecret = "client_secret"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientSecret = try container.decode(String.self, forKey: .clientSecret)

        // Handle optional ISO8601 date string
        if let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: expiresAtString)
        } else {
            expiresAt = nil
        }
    }
}

// MARK: - Token Service Errors

enum TokenServiceError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String?)
    case decodingError(Error)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error \(code): \(message ?? "Unknown")"
        case .decodingError(let error):
            return "Failed to decode token: \(error.localizedDescription)"
        case .noToken:
            return "No token received from server"
        }
    }
}

// MARK: - Token Service

final class TokenService {
    /// Shared instance
    static let shared = TokenService()

    /// Backend base URL - configure this to your server
    /// Uses same baseURL as existing APIClient for consistency
    var baseURL: String {
        APIClient.baseURL
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceMiniCog", category: "TokenService")

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    /// Fetch an ephemeral OpenAI Realtime token from your backend
    /// Backend should call OpenAI's /v1/realtime/sessions endpoint and return the client_secret
    func fetchRealtimeToken() async throws -> String {
        guard let url = URL(string: "\(baseURL)/realtime-token") else {
            throw TokenServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = ServerConfig.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TokenServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokenServiceError.serverError(statusCode: 0, message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            // Try to extract error message from response
            let message = String(data: data, encoding: .utf8)
            throw TokenServiceError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let tokenResponse = try decoder.decode(RealtimeTokenResponse.self, from: data)

            guard !tokenResponse.clientSecret.isEmpty else {
                throw TokenServiceError.noToken
            }

            #if DEBUG
            logger.debug("Token fetched, expires: \(tokenResponse.expiresAt?.description ?? "unknown", privacy: .private)")
            #endif
            return tokenResponse.clientSecret

        } catch let error as TokenServiceError {
            throw error
        } catch {
            throw TokenServiceError.decodingError(error)
        }
    }
}
