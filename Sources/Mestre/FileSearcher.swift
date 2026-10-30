import AppKit
import MestreCore

/// Runs one Spotlight query at a time, debounced, and reports paths newest-modified
/// first. The query gathers in the background; results are read on the main run loop.
@MainActor
final class FileSearcher {
    var settings = Config.Files()
    /// The text the current results answer; nil when idle.
    private(set) var text: String?
    private(set) var results: [URL] = []
    /// Fires when `results` changed.
    var onResults: (() -> Void)?

    private let query = NSMetadataQuery()
    private var pending: DispatchWorkItem?

    init() {
        query.notificationBatchingInterval = 0.1
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    /// Searches for `text` after the debounce; the same text again is a no-op.
    func search(_ text: String) {
        guard text != self.text else { return }
        self.text = text
        results = []
        pending?.cancel()
        query.stop()
        let work = DispatchWorkItem { [weak self] in self?.start(text) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.debounceSeconds, execute: work)
    }

    func cancel() {
        pending?.cancel()
        query.stop()
        text = nil
        results = []
    }

    private func start(_ text: String) {
        guard let predicate = FileSearch.predicate(for: text, minimumLength: settings.minimumLength, excludedFolders: settings.excludedFolders) else {
            results = []
            onResults?()
            return
        }
        query.predicate = predicate
        query.searchScopes = settings.folders.map(FileSearch.standardized)
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        query.start()
    }

    private func finish() {
        query.disableUpdates()
        var urls: [URL] = []
        for index in 0..<min(query.resultCount, settings.maxResults) {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        query.stop()
        results = urls
        onResults?()
    }
}
