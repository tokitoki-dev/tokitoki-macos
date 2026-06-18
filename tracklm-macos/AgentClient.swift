import Foundation

/// Talks to the local Go agent over HTTP loopback (127.0.0.1:39391).
struct AgentClient {
    static let baseURL = URL(string: "http://127.0.0.1:39391")!

    enum AgentError: Error, LocalizedError {
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Agent returned HTTP \(code)."
            }
        }
    }

    /// Historical builds used different data directories. Prefer the current
    /// TokiToki path, but accept older locations if a token-auth agent is run.
    static var tokenURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            home.appendingPathComponent(".tokitoki/agent.token"),
            home.appendingPathComponent(".goagent/agent.token"),
            base.appendingPathComponent("TokiToki/agent.token"),
            base.appendingPathComponent("TrackLM/agent.token"),
        ]
    }

    private func token() -> String? {
        for url in Self.tokenURLs {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
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

    /// Queue a WakaTime-style desktop heartbeat in the local agent.
    func recordHeartbeat(_ heartbeat: Heartbeat) async throws {
        try await post(Self.baseURL.appendingPathComponent("heartbeat"), body: heartbeat)
    }

    /// Ask the agent to shut down gracefully.
    func quit() async throws {
        try await post(Self.baseURL.appendingPathComponent("quit"))
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        authorize(&request)
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
    }

    private func post<T: Encodable>(_ url: URL, body: T) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONEncoder.agent.encode(body)
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
    }

    private func authorize(_ request: inout URLRequest) {
        guard let token = token() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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

struct Heartbeat: Encodable {
    let time: Date
    let entity: String
    let project: String
    let language: String
    let editor: String
    let type: String
}

// MARK: - Wire types (match the Go agent JSON)

private struct DailyUsageResponse: Decodable {
    let data: [DailyRow]
}

private struct DailyRow: Decodable {
    let date: String
    let total_tokens: Int?
}

private extension JSONEncoder {
    static var agent: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
