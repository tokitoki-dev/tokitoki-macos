import Foundation

/// A small adapter around the stateless Go CLI.
///
/// This follows the same short-lived-process model used by WakaTime's macOS
/// client: launch the bundled executable for one operation, collect stdout,
/// then decode its JSON contract. The Go agent owns all durable state under
/// `~/.tokitoki`.
struct AgentClient {
    let executableURL: URL

    init?(executableURL: URL? = AgentProcess.resolveBinary()) {
        guard let executableURL else { return nil }
        self.executableURL = executableURL
    }

    enum AgentError: LocalizedError {
        case commandFailed(command: String, status: Int32, stderr: String)
        case invalidResponse(command: String, underlying: Error)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(command, status, stderr):
                let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return details.isEmpty
                    ? "tokitoki \(command) failed with exit code \(status)."
                    : "tokitoki \(command) failed: \(details)"
            case let .invalidResponse(command, underlying):
                return "tokitoki \(command) returned invalid JSON: \(underlying.localizedDescription)"
            }
        }
    }

    func status() async throws -> AgentStatus {
        try await runJSON(["status"], as: AgentStatus.self)
    }

    func scan() async throws -> ScanResult {
        try await runJSON(["scan"], as: ScanResult.self)
    }

    func syncNow() async throws -> SyncResult {
        try await runJSON(["sync"], as: SyncResult.self)
    }

    /// Returns today's total across all indexed providers and projects.
    func todayTokens(now: Date = .now) async throws -> UInt64 {
        let response: DailyUsageResponse = try await runJSON(["daily", "--provider", "all"], as: DailyUsageResponse.self)
        let formatter = Self.dayFormatter
        let today = formatter.string(from: now)
        return response.data
            .filter { $0.date == today }
            .reduce(0) { $0 + $1.totalTokens }
    }

    private func runJSON<T: Decodable>(_ arguments: [String], as type: T.Type) async throws -> T {
        let command = arguments.joined(separator: " ")
        let result = try await run(arguments)
        do {
            return try JSONDecoder().decode(T.self, from: result.output)
        } catch {
            throw AgentError.invalidResponse(command: command, underlying: error)
        }
    }

    private func run(_ arguments: [String]) async throws -> CommandResult {
        let executableURL = executableURL
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.terminationHandler = { completedProcess in
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                let stderr = errors.fileHandleForReading.readDataToEndOfFile()
                let command = arguments.joined(separator: " ")

                guard completedProcess.terminationStatus == 0 else {
                    continuation.resume(throwing: AgentError.commandFailed(
                        command: command,
                        status: completedProcess.terminationStatus,
                        stderr: String(decoding: stderr, as: UTF8.self)
                    ))
                    return
                }
                continuation.resume(returning: CommandResult(output: stdout))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}

private struct CommandResult {
    let output: Data
}

struct AgentStatus: Decodable {
    let indexedEvents: Int
    let serverURL: String
    let hasAPIKey: Bool

    enum CodingKeys: String, CodingKey {
        case indexedEvents = "indexed_events"
        case serverURL = "server_url"
        case hasAPIKey = "has_api_key"
    }
}

struct ScanResult: Decodable {
    let claude: ProviderScanResult
    let codex: ProviderScanResult
}

struct ProviderScanResult: Decodable {
    let eventsInserted: Int

    enum CodingKeys: String, CodingKey {
        case eventsInserted = "events_inserted"
    }
}

struct SyncResult: Decodable {
    let ok: Bool
    let events: Int
    let accepted: Int
    let duplicate: Int
}

private struct DailyUsageResponse: Decodable {
    let data: [DailyUsageRow]
}

private struct DailyUsageRow: Decodable {
    let date: String
    let totalTokens: UInt64

    enum CodingKeys: String, CodingKey {
        case date
        case totalTokens = "total_tokens"
    }
}
