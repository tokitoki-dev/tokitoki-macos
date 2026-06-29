import Foundation

/// Resolves the stateless `tokitoki` CLI bundled with the app.
///
/// The macOS client must not start a long-lived local server. Each operation
/// invokes the CLI once and parses the JSON it writes to standard output.
enum AgentProcess {
    static func resolveBinary() -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("tokitoki")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return nil
    }
}
