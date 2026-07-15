import Foundation

/// Resolves the stateless `tokitoki` CLI and keeps the shared copy fresh.
///
/// Two layers. The shared binary at `~/.tokitoki/bin/tokitoki` wins — it is the
/// one copy every TokiToki front-end and editor plugin invokes, and the one
/// copy that updates. The binary bundled with this app is the fallback and
/// the seed: the app never downloads a CLI, it only copies its bundled build
/// into the shared location when the shared one is missing or older, then
/// lets `tokitoki upgrade` (the CLI updating itself, in Go) take it from
/// there.
///
/// The macOS client must not start a long-lived local server. Each operation
/// invokes the CLI once and parses the JSON it writes to standard output.
enum AgentProcess {
    /// The CLI shared by every TokiToki client on this machine:
    /// `~/.tokitoki/bin/tokitoki`. The `bin/` segment keeps executables apart
    /// from the data files (`api_key`, database, locks) in `~/.tokitoki`.
    /// Every front-end and editor plugin resolves this exact path — the
    /// convention is documented in tracklm-goagent/README.md.
    static var sharedBinary: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokitoki")
            .appendingPathComponent("bin")
            .appendingPathComponent("tokitoki")
    }

    static func resolveBinary() -> URL? {
        if FileManager.default.isExecutableFile(atPath: sharedBinary.path) {
            return sharedBinary
        }
        return bundledBinary()
    }

    private static func bundledBinary() -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("tokitoki")
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return nil
    }

    /// Seeds the shared CLI from the bundled copy when the shared one is
    /// missing or older. Run once at launch, before the first CLI call.
    ///
    /// Never a downgrade: an app that ships an older CLI than the shared one
    /// leaves the shared one alone. A dev build of the app (unparsable
    /// bundled version) only fills a hole, never replaces.
    static func bootstrap() async {
        guard let bundled = bundledBinary() else { return }

        let shared = sharedBinary
        let sharedExists = FileManager.default.isExecutableFile(atPath: shared.path)
        if sharedExists {
            guard let bundledVersion = await version(of: bundled) else { return }
            if let sharedVersion = await version(of: shared),
               !sharedVersion.lexicographicallyPrecedes(bundledVersion) {
                return
            }
            // Shared is older — or cannot even report a version, in which
            // case a binary that works replaces one that does not.
        }

        do {
            try seed(from: bundled, to: shared)
        } catch {
            NSLog("TokiToki: failed to seed shared CLI: %@", error.localizedDescription)
        }
    }

    /// Asks the shared CLI to update itself against the server. Silent; the
    /// CLI owns the whole check-download-verify-swap sequence, so failure
    /// here costs nothing but a log line. Run at launch and daily.
    static func upgradeSharedCLI() async {
        let shared = sharedBinary
        guard FileManager.default.isExecutableFile(atPath: shared.path) else { return }
        do {
            _ = try await run(shared, arguments: ["upgrade"])
        } catch {
            NSLog("TokiToki: shared CLI upgrade failed: %@", error.localizedDescription)
        }
    }

    /// The version a binary reports, as comparable numeric components, or
    /// nil for a build that cannot say ("dev", old CLIs, broken files).
    private static func version(of binary: URL) async -> [Int]? {
        guard let output = try? await run(binary, arguments: ["version"]) else { return nil }
        let components = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) }
        guard components.count == 3, !components.contains(nil) else { return nil }
        return components.compactMap { $0 }
    }

    /// Copies the bundled binary next to its destination and renames it into
    /// place. rename(2) is atomic, so no invocation ever sees a half-written
    /// or missing shared CLI.
    private static func seed(from bundled: URL, to shared: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: shared.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let staging = shared.appendingPathExtension("seed")
        try? fileManager.removeItem(at: staging)
        try fileManager.copyItem(at: bundled, to: staging)
        guard rename(staging.path, shared.path) == 0 else {
            try? fileManager.removeItem(at: staging)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func run(_ binary: URL, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = binary
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { completed in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard completed.terminationStatus == 0 else {
                    continuation.resume(throwing: POSIXError(.EIO))
                    return
                }
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
