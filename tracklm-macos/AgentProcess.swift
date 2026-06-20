import Foundation

/// Resolves the stateless `tokitoki` CLI bundled with the app.
///
/// The macOS client must not start a long-lived local server. Each operation
/// invokes the CLI once and parses the JSON it writes to standard output.
enum AgentProcess {
    static func resolveBinary() -> URL? {
        for key in ["TOKITOKI_AGENT_BIN", "TRACKLM_AGENT_BIN"] {
            if let override = ProcessInfo.processInfo.environment[key],
               FileManager.default.isExecutableFile(atPath: override) {
                return URL(fileURLWithPath: override)
            }
        }

        let bundled = Bundle.main.resourceURL?.appendingPathComponent("tokitoki")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        // This makes command-line and Xcode development work from either the
        // repository root or a nested project directory. Release builds use
        // the bundled resource above.
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            let candidate = directory.appendingPathComponent("tracklm-goagent/bin/tokitoki")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }
}
