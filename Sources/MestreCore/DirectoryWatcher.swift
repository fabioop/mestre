import Foundation

/// Fires a debounced callback when any of the watched directories changes
/// (an entry added, removed or renamed). Watches directories, not files: editors
/// and installers replace files by renaming temp files over them, which would
/// invalidate a descriptor opened on the file itself.
public final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let debounce: TimeInterval
    private let queue: DispatchQueue
    private let handler: () -> Void

    /// `handler` runs on `queue` after `debounce` seconds of quiet.
    public init(directories: [URL], debounce: TimeInterval = 0.2, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        self.debounce = debounce
        self.queue = queue
        self.handler = handler
        for directory in directories {
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { [weak self] in self?.schedule() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        for source in sources { source.cancel() }
        pending?.cancel()
    }

    /// Number of directories actually being watched (unreadable ones are skipped).
    public var count: Int { sources.count }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handler() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}

/// Fires a debounced callback when one file's contents change in place, which a directory
/// watch never sees (an editor or script that writes into the existing file). A rename or
/// delete ends the watch on that inode: call `rearm()` once the file may be back.
public final class FileWatcher {
    private let url: URL
    private let debounce: TimeInterval
    private let queue: DispatchQueue
    private let handler: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    public init(file: URL, debounce: TimeInterval = 0.2, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        url = file
        self.debounce = debounce
        self.queue = queue
        self.handler = handler
        rearm()
    }

    deinit {
        source?.cancel()
        pending?.cancel()
    }

    /// Whether a descriptor is open on the file right now.
    public var isWatching: Bool { source != nil }

    /// Opens the file if nothing is being watched; a no-op while the watch is alive.
    public func rearm() {
        guard source == nil else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                source.cancel()
                self.source = nil
            }
            self.schedule()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.handler() }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
