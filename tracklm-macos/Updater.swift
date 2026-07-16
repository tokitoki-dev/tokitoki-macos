import Foundation
import Sparkle

/// The auto-updater.
///
/// Sparkle does the work — downloading, verifying the EdDSA signature against
/// the public key in our Info.plist, swapping the app bundle, relaunching. What
/// this type supplies is the one thing Sparkle cannot know: *which* feed to
/// read.
///
/// The app ships as a single universal binary, but an appcast describes updates
/// for one architecture — so the feed URL cannot be a build-time constant. We
/// resolve it at runtime from the architecture we are actually executing as,
/// which is also the only way to get this right on a Rosetta-translated
/// process: an Intel-translated app on Apple Silicon must be offered the Intel
/// build, because that is what it *is*, not the arm64 one the hardware could
/// run.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController
    private let delegate = FeedDelegate()

    init() {
        controller = SPUStandardUpdaterController(
            // Sparkle starts itself and begins its background schedule.
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
    }

    /// The user asked. Always shows UI, including "you're up to date".
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Whether a check is possible right now (Sparkle disables it mid-update).
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Sparkle owns the schedule and persists this itself.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}

/// Supplies the feed URL for the architecture this process is running as.
private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        AppConfig.serverURL
            .appendingPathComponent("api/updates/appcast/macos/\(Arch.current)")
            .absoluteString
    }
}

/// The architecture of the running process — not of the machine.
///
/// `uname` reports the hardware, which is the wrong question: under Rosetta the
/// hardware is arm64 while the process, and therefore the app that must be
/// replaced, is x86_64. The compile-time check answers what we actually run as,
/// and in a universal binary both slices are compiled, so each slice gets the
/// answer that is true for itself.
private enum Arch {
    static var current: String {
        #if arch(arm64)
            return "arm64"
        #else
            return "amd64"
        #endif
    }
}
