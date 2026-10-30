import Combine
import Foundation
import MestreCore

/// Owns the app list: scans off the main thread, watches the scanned folders so
/// installs show up at once, and serialises rescans so a change arriving mid-scan
/// is never lost.
@MainActor
final class AppIndex: ObservableObject {
    struct Scope: Equatable {
        var directories: [URL]
        var depth: Int
        var watchFolders: Bool
        var refreshInterval: TimeInterval
    }

    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var isIndexing = false

    private var scope: Scope?
    private var watcher: DirectoryWatcher?
    private var lastIndexed: Date?
    private var dirty = false

    func apply(_ scope: Scope) {
        let previous = self.scope
        self.scope = scope
        if !scope.watchFolders { watcher = nil }
        let scanAgain = previous == nil
            || previous?.directories != scope.directories
            || previous?.depth != scope.depth
            || (scope.watchFolders && watcher == nil)
        if scanAgain { rescan() }
    }

    func rescan() {
        guard let scope else { return }
        guard !isIndexing else { dirty = true; return }
        isIndexing = true
        let (directories, depth) = (scope.directories, scope.depth)
        Task {
            let start = ContinuousClock.now
            let result = await Task.detached(priority: .userInitiated) {
                AppIndexer.scan(directories: directories, maxDepth: depth)
            }.value
            Perf.log("index scan (\(result.entries.count) apps)", since: start)
            finish(result)
        }
    }

    /// Optional periodic fallback (`search.refreshIntervalSeconds`), checked when the panel opens.
    func refreshIfStale() {
        guard let scope, scope.refreshInterval > 0, let lastIndexed,
              Date().timeIntervalSince(lastIndexed) > scope.refreshInterval else { return }
        rescan()
    }

    private func finish(_ result: AppIndexer.ScanResult) {
        apps = result.entries
        lastIndexed = Date()
        isIndexing = false
        // Rebuilt after every scan so new subfolders (and a ~/Applications that
        // appeared later) are covered without a config change.
        if scope?.watchFolders == true {
            watcher = DirectoryWatcher(directories: result.watchedDirectories, debounce: 1.0) { [weak self] in
                self?.rescan()
            }
        }
        if dirty {
            dirty = false
            rescan()
        }
    }
}
