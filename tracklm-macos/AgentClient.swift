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

        var errorDescription: String? {
            switch self {
            case let .commandFailed(status, _):
                return "TokiToki upload failed (exit \(status))."
            case let .invalidResponse(error):
                return "TokiToki returned invalid JSON: \(error.localizedDescription)"
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
            case .invalidResponse:
                return "Agent returned an unexpected response"
            }
        }
    }

    func sync(apiKey: String? = nil, providers: [String]? = nil) async throws {
        var arguments: [String] = []
        var input: Data?
        if let apiKey {
            arguments.append("--api-key-stdin")
            input = Data((apiKey + "\n").utf8)
        }
        if let providers {
            arguments += ["--providers", providers.joined(separator: ",")]
        }

        let result = try await run(arguments, input: input)
        do {
            let response = try JSONDecoder().decode(SyncResponse.self, from: result.output)
            guard response.ok else { throw AgentError.invalidResponse(AgentError.commandFailed(status: 1, stderr: "")) }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.invalidResponse(error)
        }
    }

    private func run(_ arguments: [String], input: Data?) async throws -> CommandResult {
        let executableURL = executableURL
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            let inputPipe = input.map { _ in Pipe() }

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = errors
            process.standardInput = inputPipe
            process.terminationHandler = { completedProcess in
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                let stderr = errors.fileHandleForReading.readDataToEndOfFile()
                guard completedProcess.terminationStatus == 0 else {
                    continuation.resume(throwing: AgentError.commandFailed(
                        status: completedProcess.terminationStatus,
                        stderr: String(decoding: stderr, as: UTF8.self)
                    ))
                    return
                }
                continuation.resume(returning: CommandResult(output: stdout))
            }

            do {
                try process.run()
                if let input, let inputPipe {
                    inputPipe.fileHandleForWriting.write(input)
                    try? inputPipe.fileHandleForWriting.close()
                }
            } catch {
                continuation.resume(throwing: error)
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
