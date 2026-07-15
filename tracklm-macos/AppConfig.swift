import Foundation

/// Where this build talks to.
///
/// Baked in at build time (`TOKITOKI_SERVER_URL` → `TokiTokiServerURL` in the
/// generated Info.plist): Debug points at a local dev server, Release at
/// production. The dashboard link and the update feed both come from here, so a
/// build cannot end up checking one host for updates while sending its user to
/// another.
enum AppConfig {
    static let serverURL: URL = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "TokiTokiServerURL") as? String
        guard let configured, let url = URL(string: configured.trimmingCharacters(in: .whitespaces)),
              url.scheme == "http" || url.scheme == "https"
        else {
            // A build with no server configured is a build that cannot work.
            // Failing here, loudly, beats silently pointing at localhost in
            // something a user installed.
            fatalError("TokiTokiServerURL is missing or not an http(s) URL")
        }
        return url
    }()

    /// The current app version, as the server understands it (semver).
    static let version: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
}
