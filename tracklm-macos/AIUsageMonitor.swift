import CoreServices
import Foundation

/// Recursively watches the local Claude Code and Codex data directories.
/// FSEvents coalesces nested file writes; this type adds a short debounce so a
/// streaming transcript produces one CLI invocation rather than many.
@MainActor
final class AIUsageMonitor {
    private var stream: FSEventStreamRef?
    private var debounceTask: Task<Void, Never>?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        stop()
        let paths = AgentDataDirectories.watchPaths()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func recordChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }

    private nonisolated static let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let monitor = Unmanaged<AIUsageMonitor>.fromOpaque(info).takeUnretainedValue()
        Task { @MainActor in
            monitor.recordChange()
        }
    }

}
