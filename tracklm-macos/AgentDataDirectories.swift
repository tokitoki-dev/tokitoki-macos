import Foundation

enum AgentDataDirectories {
    nonisolated static let allProviders: [String] = [
        "claude", "codex", "copilot", "gemini", "kimi", "qwen", "openclaw",
        "pi", "amp", "droid", "kilo", "hermes", "codebuff", "opencode", "goose",
    ]

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
        case "droid":
            return configuredPaths("DROID_SESSIONS_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory/sessions").path]
        case "kilo":
            return configuredPaths("KILO_DATA_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/kilo").path]
        case "hermes":
            return configuredPaths("HERMES_HOME")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes").path]
        case "codebuff":
            return configuredPaths("CODEBUFF_DATA_DIR")
                ?? [
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/manicode").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/manicode-dev").path,
                    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/manicode-staging").path,
                ]
        case "opencode":
            return configuredPaths("OPENCODE_DATA_DIR")
                ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode").path]
        case "goose":
            if let configured = configuredPaths("GOOSE_PATH_ROOT") {
                return configured.map {
                    URL(fileURLWithPath: $0)
                        .appendingPathComponent("data/sessions/sessions.db")
                        .path
                }
            }
            return [
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/goose/sessions/sessions.db").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/goose/sessions/sessions.db").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/Block/goose/sessions/sessions.db").path,
            ]
        default:
            return []
        }
    }

    nonisolated static func watchPaths() -> [String] {
        Array(Set(allProviders.flatMap(paths(for:)).compactMap(existingWatchDirectory))).sorted()
    }

    nonisolated static func syncArguments() -> [String] {
        var arguments: [String] = []
        for provider in allProviders {
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
