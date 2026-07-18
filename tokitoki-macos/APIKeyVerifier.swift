import Foundation

/// Verifies a key directly with the configured TokiToki server.
///
/// The session is ephemeral so a credential check cannot leave cookies or a
/// cached response behind. The key exists only in the request header and is
/// never placed in a URL, error message, or stored property.
nonisolated struct APIKeyVerifier: Sendable {
    enum VerificationError: LocalizedError {
        case invalidResponse
        case serviceUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "TokiToki returned an invalid verification response."
            case .serviceUnavailable:
                return "TokiToki verification is temporarily unavailable."
            }
        }
    }

    private struct VerificationResponse: Decodable {
        let valid: Bool
    }

    private let serverURL: URL
    private let session: URLSession

    init(serverURL: URL, session: URLSession = APIKeyVerifier.makeEphemeralSession()) {
        self.serverURL = serverURL
        self.session = session
    }

    func verify(_ apiKey: String) async throws -> Bool {
        let endpoint = serverURL.appending(
            path: "api/auth/api-key/verify",
            directoryHint: .notDirectory
        )
        var request = URLRequest(
            url: endpoint,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw VerificationError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let payload: VerificationResponse
            do {
                payload = try JSONDecoder().decode(VerificationResponse.self, from: data)
            } catch {
                throw VerificationError.invalidResponse
            }
            guard payload.valid else {
                throw VerificationError.invalidResponse
            }
            return true
        case 401:
            return false
        default:
            throw VerificationError.serviceUnavailable
        }
    }

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }
}
