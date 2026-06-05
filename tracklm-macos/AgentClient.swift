import Foundation

/// Talks to the local Go agent over HTTP loopback (127.0.0.1:39391).
///
/// The agent's protected endpoints require `Authorization: Bearer <token>`,
/// where the token lives in a file the agent writes on first run:
///   ~/.goagent/agent.token
/// Both processes share the filesystem, so reading that file is the whole
/// "key handshake" — no extra IPC needed.
struct AgentClient {
    static let baseURL = URL(string: "http://127.0.0.1:39391")!

    enum AgentError: Error, LocalizedError {
        case tokenUnavailable
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .tokenUnavailable: return "Agent token not found yet."
            case .http(let code): return "Agent returned HTTP \(code)."
            }
        }
    }

    /// Location of the token file written by the Go store package.
    static var tokenURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let primary = home.appendingPathComponent(".goagent/agent.token")
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TrackLM/agent.token")
    }

    private func token() throws -> String {
        guard let raw = try? String(contentsOf: Self.tokenURL, encoding: .utf8) else {
            throw AgentError.tokenUnavailable
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw AgentError.tokenUnavailable }
        return trimmed
    }

    // MARK: - Public API

    /// `/health` needs no auth — the cheapest "is it alive" probe.
    func isHealthy() async -> Bool {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return http.statusCode == 200
    }

    /// Sum of today's total tokens across all providers.
    func todayTokens() async throws -> Int {
        let url = Self.baseURL.appendingPathComponent("usage/daily")
            .appending(queryItems: [URLQueryItem(name: "provider", value: "all")])
        let payload: DailyUsageResponse = try await get(url)

        let today = Self.todayString()
        return payload.data
            .filter { $0.date == today }
            .reduce(0) { $0 + ($1.total_tokens ?? 0) }
    }

    /// Trigger a scan + upload to the cloud now.
    func syncNow() async throws {
        try await post(Self.baseURL.appendingPathComponent("sync"))
    }

    /// Ask the agent to shut down gracefully.
    func quit() async throws {
        try await post(Self.baseURL.appendingPathComponent("quit"))
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AgentError.http(http.statusCode)
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

// MARK: - Wire types (match the Go agent JSON)

private struct DailyUsageResponse: Decodable {
    let data: [DailyRow]
}

private struct DailyRow: Decodable {
    let date: String
    let total_tokens: Int?
}
