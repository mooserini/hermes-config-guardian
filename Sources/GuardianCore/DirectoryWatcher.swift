import Darwin
import Foundation

public enum DirectoryWatcherError: LocalizedError {
    case unableToOpenDirectory(String)

    public var errorDescription: String? {
        switch self {
        case let .unableToOpenDirectory(path):
            return "Unable to watch the directory containing \(path)."
        }
    }
}

public final class DirectoryWatcher: @unchecked Sendable {
    private let targetURL: URL
    private let watchAncestorDirectory: Bool
    private let queue: DispatchQueue
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingWork: DispatchWorkItem?
    private var descriptor: Int32 = -1

    public init(
        targetURL: URL,
        debounceInterval: TimeInterval = 0.35,
        watchAncestorDirectory: Bool = true,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.targetURL = targetURL
        self.watchAncestorDirectory = watchAncestorDirectory
        self.debounceInterval = debounceInterval
        self.onChange = onChange
        self.queue = DispatchQueue(label: "org.hermesconfigguardian.watcher", qos: .utility)
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard source == nil else { return }
        let directory = watchAncestorDirectory ? targetURL.deletingLastPathComponent() : targetURL
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw DirectoryWatcherError.unableToOpenDirectory(directory.path)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib, .extend],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        self.source = source
        source.resume()
    }

    public func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        source?.cancel()
        source = nil
    }

    private func scheduleChange() {
        pendingWork?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pendingWork = work
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
