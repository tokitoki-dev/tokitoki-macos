import Foundation

enum AgentDataDirectories {
    static func paths(for provider: String) -> [String] {
        switch provider {
        case "claude":
            return claudePaths()
        case "codex":
            return codexPaths()
        default:
            return []
        }
    }

    static func watchPaths(for providers: [String]) -> [String] {
        Array(Set(providers.flatMap(paths(for:)).filter(isExistingDirectory))).sorted()
    }

    static func syncArguments(for providers: [String]) -> [String] {
        var arguments: [String] = []
        if providers.contains("claude"), let path = paths(for: "claude").first(where: isExistingDirectory) {
            arguments += ["--claude-dir", path]
        }
        if providers.contains("codex"), let path = paths(for: "codex").first(where: isExistingDirectory) {
            arguments += ["--codex-dir", path]
        }
        return arguments
    }

    private static func claudePaths() -> [String] {
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

    private static func codexPaths() -> [String] {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let configured = environment["CODEX_CONFIG_DIR"] {
            return configured.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).path
            }
        }
        return [home.appendingPathComponent(".codex").path]
    }

    private static func isExistingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
