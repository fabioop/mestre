import AppKit
import MestreCore

struct QuicklinkItem: SearchItem {
    let link: Quicklink
    /// Text after the keyword, empty in name form.
    let query: String
    let keywords: [String]

    init(link: Quicklink, query: String) {
        self.link = link
        self.query = query
        keywords = link.keyword.map { [$0] } ?? []
    }

    var resolved: URL? { link.resolvedURL(query: query) }
    var needsQuery: Bool { link.takesQuery && query.isEmpty }

    var id: String { link.id }
    var title: String { link.takesQuery && !query.isEmpty ? "\(link.name): \(query)" : link.name }
    var subtitle: String? { needsQuery ? "Type \(link.completionPrefix)… to search" : resolved?.absoluteString ?? link.url }
    var subtitleRole: SubtitleRole { needsQuery ? .content : .metadata }
    var icon: NSImage? { nil }
    var iconSymbol: String? { link.takesQuery ? "magnifyingglass" : "link" }
    var kind: ItemKind { .quicklink }
    var actions: [ItemAction] { needsQuery ? Self.completeActions : Self.openActions }

    static let openActions = ItemAction.urlActions
    static let completeActions = [ItemAction(id: "complete", title: "Search…", icon: "text.cursor")]
}

/// User-defined links from config. "gh swift" with keyword "gh" fills the search
/// placeholder; a link without a placeholder ranks by name like an app. Picking a
/// search link by name completes the search box to its keyword.
@MainActor
final class QuicklinkProvider: ResultProvider {
    nonisolated let id = "quicklinks"
    nonisolated let declaredActions = QuicklinkItem.openActions + QuicklinkItem.completeActions

    var links: [Quicklink] = [] {
        didSet {
            // First definition wins for a repeated name or keyword; the id must stay unique.
            var names = Set<String>()
            let unique = links.filter { names.insert($0.name).inserted }
            if unique.count != links.count { links = unique }
            byKeyword = Dictionary(links.compactMap { link in link.keyword.map { ($0, link) } }, uniquingKeysWith: { first, _ in first })
            keywords = Set(byKeyword.keys)
            nameItems = links.map { QuicklinkItem(link: $0, query: "") }
        }
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    private(set) var keywords: Set<String> = []

    func owns(_ query: Query) -> Bool { query.firstWord.map(keywords.contains) ?? false }

    private var byKeyword: [String: Quicklink] = [:]
    private var nameItems: [QuicklinkItem] = []

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard !query.isEmpty else { return [] }
        // Keyword form: "gh swift" → the one link, with the rest as its query.
        if let word = query.firstWord, let link = byKeyword[word] {
            return [ScoredItem(item: QuicklinkItem(link: link, query: query.remainder), score: ScoredItem.pinnedScore, provider: self)]
        }
        // Name form after completion: "GitHub search swift".
        for link in links where link.takesQuery && link.keyword == nil {
            let prefix = link.name.lowercased() + " "
            if query.lowercased.hasPrefix(prefix) {
                let rest = String(query.text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return [ScoredItem(item: QuicklinkItem(link: link, query: rest), score: ScoredItem.pinnedScore, provider: self)]
            }
        }
        return Ranker.rank(nameItems, query: query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let item = item as? QuicklinkItem else { return }
        switch action.id {
        case "complete":
            replaceQuery?(item.link.completionPrefix)
        case "open":
            guard let url = item.resolved else { NSSound.beep(); return }
            dismiss?()
            if !NSWorkspace.shared.open(url) { NSLog("Quicklink %@: could not open %@", item.link.name, url.absoluteString) }
        case "copyURL":
            guard let url = item.resolved else { NSSound.beep(); return }
            url.absoluteString.copyToPasteboard(toast: "URL copied")
        default: NSSound.beep()
        }
    }
}
