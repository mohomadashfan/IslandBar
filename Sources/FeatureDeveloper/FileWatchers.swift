import CoreServices
import Foundation

/// Recursive directory watcher built on FSEvents. Events are delivered on the main queue.
/// Call `stop()` before releasing it.
@MainActor
final class FileEventStream {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private let handler: @MainActor ([String]) -> Void

    init(paths: [String], latency: CFTimeInterval = 1.0, handler: @escaping @MainActor ([String]) -> Void) {
        self.paths = paths
        self.latency = latency
        self.handler = handler
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let array = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let changed = Array(array.prefix(count))
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated {
                let watcher = Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue()
                watcher.handler(changed)
            }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Watches a single directory for entries being added, using a vnode dispatch source.
/// Call `stop()` before releasing it.
@MainActor
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let handler: @MainActor () -> Void

    init(url: URL, handler: @escaping @MainActor () -> Void) {
        self.url = url
        self.handler = handler
    }

    func start() -> Bool {
        guard source == nil else { return true }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        let handler = handler
        source.setEventHandler {
            MainActor.assumeIsolated { handler() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
