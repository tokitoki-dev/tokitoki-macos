import Foundation

/// Runs the one-operation Go CLI. Calling the executable always scans selected
/// local AI clients and uploads the resulting events to localhost:9093.
struct AgentClient {
    let executableURL: URL

    init?(executableURL: URL? = AgentProcess.resolveBinary()) {
        guard let executableURL else { return nil }
        self.executableURL = executableURL
    }

    enum AgentError: LocalizedError {
        case commandFailed(status: Int32, stderr: String)
        case invalidResponse(Error)
        case rejected

        var errorDescription: String? {
            switch self {
            case let .commandFailed(status, _):
                return "TokiToki upload failed (exit \(status))."
            case let .invalidResponse(error):
                return "TokiToki returned invalid JSON: \(error.localizedDescription)"
            case .rejected:
                return "TokiToki reported failure."
            }
        }

        var menuMessage: String {
            switch self {
            case let .commandFailed(_, stderr):
                let details = stderr.lowercased()
                if details.contains("api key") {
                    return "Set an API key in Settings"
                }
                if details.contains("timeout") || details.contains("database") {
                    return "Local usage database is busy"
                }
                return "Unable to sync local usage"
            case .invalidResponse, .rejected:
                return "Agent returned an unexpected response"
            }
        }

        var isMissingAPIKey: Bool {
            guard case let .commandFailed(_, stderr) = self else { return false }
            return stderr.lowercased().contains("api key")
        }
    }

    func sync() async throws {
        let arguments = AgentDataDirectories.syncArguments()
        guard !arguments.isEmpty else { return }
        try requireOK(try await run(arguments, input: nil))
    }

    func setAPIKey(_ apiKey: String) async throws {
        try requireOK(try await run(["set", "key", apiKey], input: nil))
    }

    func getAPIKey() async throws -> String {
        let result = try await run(["get", "key"], input: nil)
        return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A one-time URL that opens the web dashboard already signed in. The CLI
    /// exchanges the stored API key for it server-side; the key itself never
    /// appears in the URL.
    func dashboardURL() async throws -> URL {
        let result = try await run(["get", "dashboard-url"], input: nil)
        let raw = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme == "http" || url.scheme == "https" else {
            throw AgentError.invalidResponse(URLError(.badURL))
        }
        return url
    }

    /// The CLI exited 0 but its JSON answer decides success: `{"ok":true}`.
    private func requireOK(_ result: CommandResult) throws {
        let response: SyncResponse
        do {
            response = try JSONDecoder().decode(SyncResponse.self, from: result.output)
        } catch {
            throw AgentError.invalidResponse(error)
        }
        guard response.ok else { throw AgentError.rejected }
    }

    private func run(_ arguments: [String], input: Data?) async throws -> CommandResult {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let inputPipe = input.map { _ in Pipe() }

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = inputPipe

        let (exit, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { completed in
            exitContinuation.yield(completed.terminationStatus)
            exitContinuation.finish()
        }

        try process.run()
        if let input, let inputPipe {
            inputPipe.fileHandleForWriting.write(input)
            try? inputPipe.fileHandleForWriting.close()
        }

        // Drain both pipes while the process runs. Waiting for termination
        // first would deadlock as soon as the CLI writes a pipe buffer's
        // worth: it blocks on a full pipe, and the exit never comes.
        async let stdout = Self.readToEnd(output)
        async let stderr = Self.readToEnd(errors)

        var status: Int32 = -1
        for await exitStatus in exit {
            status = exitStatus
        }

        guard status == 0 else {
            throw AgentError.commandFailed(
                status: status,
                stderr: String(decoding: await stderr, as: UTF8.self)
            )
        }
        return CommandResult(output: await stdout)
    }

    private static func readToEnd(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }
}

private struct CommandResult {
    let output: Data
}

private struct SyncResponse: Decodable {
    let ok: Bool
}
