//
//  APIService.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import Foundation

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL."
        case .badResponse(let code): return "Server returned status code \(code)."
        case .decodingError(let msg): return "Data parsing error: \(msg)"
        }
    }
}

// MARK: - APIService

final class APIService: Sendable {

    static let shared = APIService()
    private init() {}

    private let endpoint = "https://jsonplaceholder.typicode.com/users"

    func fetchUsers() async throws -> [UserProfile] {
        guard let url = URL(string: endpoint) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.badResponse(http.statusCode)
        }

        do {
            return try JSONDecoder().decode([UserProfile].self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
