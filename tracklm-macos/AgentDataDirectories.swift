import Foundation

enum AgentDataDirectories {
    nonisolated static func paths(for provider: String) -> [String] {
        switch provider {
        case "claude":
            return claudePaths()
        case "codex":
            return codexPaths()
        case "copilot":
            return configuredPaths("COPILOT_OTEL_FILE_EXPORTER_PATH")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot/otel").path]
        case "gemini":
            return configuredPaths("GEMINI_DATA_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/tmp").path]
        case "kimi":
            return configuredPaths("KIMI_DATA_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".kimi").path]
        case "qwen":
            return configuredPaths("QWEN_DATA_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qwen").path]
        case "openclaw":
            return configuredPaths("OPENCLAW_DIR")
                ?? [
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".openclaw").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".clawdbot").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".moltbot").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".moldbot").path,
                ]
        case "pi":
            return configuredPaths("PI_AGENT_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent/sessions").path]
        case "amp":
            return configuredPaths("AMP_DATA_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/amp").path]
        default:
            return []
        }
    }

    nonisolated static func watchPaths(for providers: [String]) -> [String] {
        Array(Set(providers.flatMap(paths(for:)).compactMap(existingWatchDirectory))).sorted()
    }

    nonisolated static func syncArguments(for providers: [String]) -> [String] {
        var arguments: [String] = []
        for provider in providers {
            if let path = paths(for: provider).first(where: isExistingPath) {
                arguments += ["--provider-dir", "\(provider)=\(path)"]
            }
        }
        return arguments
    }

    private nonisolated static func claudePaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let configured = environment["CLAUDE_CONFIG_DIR"] {
            return configured.split(separator: ",").map { raw in
                let path = URL(fileURLWithPath: String(raw).trimmingCharacters(in: .whitespaces))
                return path.lastPathComponent == "projects" ? path.deletingLastPathComponent().path : path.path
            }
        }

        let xdg = environment["XDG_CONFIG_HOME"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".config")
        return [
            home.appendingPathComponent(".claude").path,
            xdg.appendingPathComponent("claude").path,
        ]
    }

    private nonisolated static func codexPaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let configured = environment["CODEX_CONFIG_DIR"] {
            return configured.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).path
            }
        }
        return [home.appendingPathComponent(".codex").path]
    }

    private nonisolated static func configuredPaths(_ key: String) -> [String]? {
        guard let configured = ProcessInfo.processInfo.environment[key] else { return nil }
        let paths = configured.split(separator: ",").map {
            URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).path
        }.filter { !$0.isEmpty }
        return paths.isEmpty ? nil : paths
    }

    private nonisolated static func isExistingPath(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private nonisolated static func existingWatchDirectory(_ path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue {
            return path
        }
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var parentIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue else { return nil }
        return parent
    }
}
