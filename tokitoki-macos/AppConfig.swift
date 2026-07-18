import Foundation

/// The one server configuration shared by the native app and its CLI child.
///
/// `TOKITOKI_BASE_URL` is a runtime override for local and staging tests. A
/// normally launched app has no such override and talks to the public server.
enum AppConfig {
    nonisolated static let baseURLEnvironmentKey = "TOKITOKI_BASE_URL"
    nonisolated static let defaultServerURL = URL(string: "https://tokitoki.dev")!

    nonisolated static let serverURL = resolveServerURL(
        environment: ProcessInfo.processInfo.environment
    )

    nonisolated static func resolveServerURL(environment: [String: String]) -> URL {
        guard let value = environment[baseURLEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return defaultServerURL
        }
        guard let url = URL(string: value),
              url.scheme == "http" || url.scheme == "https",
              url.host != nil
        else {
            fatalError("\(baseURLEnvironmentKey) is not an http(s) server URL")
        }
        return url
    }

    /// Passes the resolved URL to every CLI invocation even when macOS started
    /// the app through Finder and supplied no shell environment.
    nonisolated static func processEnvironment(
        inheriting environment: [String: String],
        serverURL: URL
    ) -> [String: String] {
        var result = environment
        result[baseURLEnvironmentKey] = serverURL.absoluteString
        return result
    }

    /// The current app version, as the server understands it (semver).
    nonisolated static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
}
