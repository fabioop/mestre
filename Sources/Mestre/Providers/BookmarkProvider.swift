import AppKit
import MestreCore

struct BookmarkItem: SearchItem {
    let bookmark: Bookmark
    let keywords: [String]
    let subtitle: String?

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        keywords = [bookmark.host]
        subtitle = [bookmark.browser.name, bookmark.folder.nilIfEmpty, bookmark.host.nilIfEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    var id: String { bookmark.id }
    var title: String { bookmark.title }
    var icon: NSImage? { MainActor.assumeIsolated { BookmarkProvider.icon(for: bookmark.browser) } }
    var iconSymbol: String? { "bookmark" }
    var kind: ItemKind { .bookmark }
    var actions: [ItemAction] { ItemAction.urlActions }
}

/// Bookmarks from every Chromium-family browser and Firefox profile on this Mac.
/// Read off the main thread, and re-read when the panel opens and a bookmark file
/// changed since (checked by modification date and size: no watcher, no idle cost).
/// "bm <text>" searches them, or every query does with `bookmarks.searchEverywhere`.
@MainActor
final class BookmarkProvider: ResultProvider {
    nonisolated let id = "bookmarks"
    nonisolated let declaredActions = ItemAction.urlActions

    var settings = Config.Bookmarks() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
            if !settings.enabled {
                items = []
                fingerprints = []
            } else if !oldValue.enabled || oldValue.excludeBrowsers != settings.excludeBrowsers || items.isEmpty {
                reload()
            }
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Bookmarks().keyword)
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var items: [BookmarkItem] = []
    /// Fingerprints of the files the current items came from.
    private var fingerprints: [String] = []
    private var loading = false
    private var dirty = false

    private static var icons: [Browser: NSImage?] = [:]

    static func icon(for browser: Browser) -> NSImage? {
        if let cached = icons[browser] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier).map { NSWorkspace.shared.cachedIcon(forFile: $0.path) }
        icons[browser] = icon
        return icon
    }

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func panelWillShow() {
        guard settings.enabled else { return }
        let excluded = Set(settings.excludeBrowsers.map { $0.lowercased() })
        let known = fingerprints
        Task {
            let current = await Task.detached(priority: .utility) {
                Bookmarks.sources().filter { !excluded.contains($0.browser.rawValue) }.map(\.fingerprint)
            }.value
            if current != known { reload() }
        }
    }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "bookmarks", title: "Browser Bookmarks", subtitle: "Chrome, Brave, Edge, Vivaldi, Arc and Firefox", symbol: "bookmark", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, !items.isEmpty else { return [] }
        if mode.matches(query) {
            let text = query.remainder
            return text.isEmpty ? ScoredItem.pinned(Array(items.prefix(limit)), provider: self) : Ranker.rank(items, query: text, limit: limit, provider: self)
        }
        guard settings.searchEverywhere, query.text.count >= settings.minimumLength else { return [] }
        return Ranker.rank(items, query: query.text, limit: limit, provider: self, boost: { _ in -settings.penalty })
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let bookmark = (item as? BookmarkItem)?.bookmark, let url = URL(string: bookmark.url) else { NSSound.beep(); return }
        switch action.id {
        case "open":
            dismiss?()
            if settings.openInSourceBrowser, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bookmark.browser.bundleIdentifier) {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        case "copyURL": bookmark.url.copyToPasteboard(toast: "URL copied")
        default: NSSound.beep()
        }
    }

    private func reload() {
        guard !loading else { dirty = true; return }
        loading = true
        let excluded = Set(settings.excludeBrowsers.map { $0.lowercased() })
        Task {
            let (loaded, prints) = await Task.detached(priority: .utility) { () -> ([BookmarkItem], [String]) in
                let sources = Bookmarks.sources().filter { !excluded.contains($0.browser.rawValue) }
                return (sources.flatMap { $0.read() }.map(BookmarkItem.init), sources.map(\.fingerprint))
            }.value
            loading = false
            if settings.enabled {
                items = loaded
                fingerprints = prints
                onChange?()
            }
            if dirty { dirty = false; reload() }
        }
    }
}
