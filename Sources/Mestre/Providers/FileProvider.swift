import AppKit
import MestreCore

/// A file or folder on disk, from search results or folder browsing.
struct FileItem: SearchItem, Equatable {
    static func == (lhs: FileItem, rhs: FileItem) -> Bool { lhs.url == rhs.url && lhs.isDirectory == rhs.isDirectory }

    let url: URL
    var isDirectory = false
    /// For browsing: what the search box should become to step into this folder.
    var completion: String?

    var id: String { url.path }
    var title: String { url.lastPathComponent + (isDirectory ? "/" : "") }
    var subtitle: String? { FileSearch.folderDescription(of: url.path) }
    /// Resolved when the row renders, cached by path.
    var icon: NSImage? { NSWorkspace.shared.cachedIcon(forFile: url.path) }
    var kind: ItemKind { .file }
    var actions: [ItemAction] { isDirectory && completion != nil ? Self.folderActions : Self.fileActions }

    static let fileActions: [ItemAction] = [.open, .quickLook, .reveal, .copyPath]
    static let folderActions: [ItemAction] = [
        ItemAction(id: "enter", title: "Open Folder", icon: "arrow.right.circle"),
        ItemAction(id: "finder", title: "Open in Finder", icon: "folder"),
        .copyPath,
    ]
}

/// "file report" searches file names through Spotlight in the configured folders.
/// Results arrive asynchronously and refresh the list.
@MainActor
final class FileProvider: ResultProvider {
    nonisolated let id = "files"
    nonisolated let declaredActions = FileItem.fileActions + FileItem.folderActions

    var settings = Config.Files() {
        didSet {
            searcher.settings = settings
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Files().keyword)
    func owns(_ query: Query) -> Bool { mode.matches(query) }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)? {
        didSet { searcher.onResults = onChange }
    }
    var replaceQuery: ((String) -> Void)?

    private let searcher = FileSearcher()

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "files", title: "Search Files", subtitle: "Spotlight search by name. ⌘Y Quick Look, ⌘↩ reveal", symbol: "doc.text.magnifyingglass", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard mode.matches(query) else { return [] }
        let text = query.remainder
        if text.isEmpty { searcher.cancel() } else { searcher.search(text) }
        return ScoredItem.pinned(searcher.results.prefix(limit).map { FileItem(url: $0) }, provider: self)
    }

    /// Another provider took the query: drop the in-flight search and its results.
    func queryLeft() { searcher.cancel() }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let url = (item as? FileItem)?.url else { return }
        if !FileActions.perform(action, on: url, dismiss: dismiss) { NSSound.beep() }
    }
}
