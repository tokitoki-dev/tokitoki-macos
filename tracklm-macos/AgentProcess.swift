import Foundation

/// Launches and supervises the Go agent as a child (sidecar) process.
///
/// The agent binary is expected next to the app, or found via the
/// TRACKLM_AGENT_BIN env var (handy during development). When this app exits,
/// the child is terminated too — no orphaned agent left running.
final class AgentProcess {
    private var process: Process?

    /// Resolve the agent binary path: env override first, then a few dev paths.
    static func resolveBinary() -> URL? {
        if let override = ProcessInfo.processInfo.environment["TRACKLM_AGENT_BIN"],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        // Alongside the app bundle's executable (production layout).
        let exeDir = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates = [
            exeDir?.appendingPathComponent("tracklm-agent"),
            // Dev layout: ../tracklm-goagent/bin/tracklm-agent from repo root.
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("../tracklm-goagent/bin/tracklm-agent"),
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Returns true if it started a process (false if already running or binary missing).
    @discardableResult
    func start() -> Bool {
        guard process == nil else { return false }
        guard let binary = Self.resolveBinary() else {
            NSLog("TrackLM: agent binary not found; set TRACKLM_AGENT_BIN")
            return false
        }

        let proc = Process()
        proc.executableURL = binary

        do {
            try proc.run()
            process = proc
            NSLog("TrackLM: started agent at \(binary.path)")
            return true
        } catch {
            NSLog("TrackLM: failed to start agent: \(error)")
            return false
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
