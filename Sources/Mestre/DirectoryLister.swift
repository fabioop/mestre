import Foundation
import MestreCore

/// Folder listings for path browsing, read off the main thread and kept for a few
/// seconds so each keystroke filters in memory.
@MainActor
final class DirectoryLister {
    var ttl: TimeInterval = 5
    /// Fires when a listing that was requested has arrived.
    var onLoaded: (() -> Void)?

    private var cache: [String: (entries: [PathCompletion.Entry], at: Date)] = [:]
    private var loading: Set<String> = []

    /// The cached listing, or nil while it loads (the caller is told through `onLoaded`).
    func entries(of directory: String) -> [PathCompletion.Entry]? {
        if let cached = cache[directory], Date().timeIntervalSince(cached.at) < ttl { return cached.entries }
        guard !loading.contains(directory) else { return cache[directory]?.entries }
        loading.insert(directory)
        Task {
            let entries = await Task.detached(priority: .userInitiated) { PathCompletion.list(directory) }.value
            cache[directory] = (entries, Date())
            loading.remove(directory)
            if cache.count > 16 { cache = cache.filter { Date().timeIntervalSince($0.value.at) < ttl } }
            onLoaded?()
        }
        return cache[directory]?.entries
    }

    func clear() { cache.removeAll() }
}
