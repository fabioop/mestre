import AppKit
import MestreCore

/// A typed address. The URL is already known.
struct WebAddressItem: SearchItem {
    let text: String
    let url: URL

    var id: String { "open" }
    var title: String { "Open \(text)" }
    var subtitle: String? { url.absoluteString }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "globe" }
    var kind: ItemKind { .web }
    var actions: [ItemAction] { ItemAction.urlActions }
}

/// The last row: search the engine for whatever was typed. The URL is built only
/// when the row renders or runs, never per keystroke.
struct WebSearchItem: SearchItem {
    let text: String
    let engine: String

    var url: URL? { WebQuery.searchURL(engine: engine, query: text) }
    var id: String { "search" }
    var title: String { "Search the web for “\(text)”" }
    var subtitle: String? { url?.absoluteString }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "magnifyingglass.circle" }
    var kind: ItemKind { .web }
    var actions: [ItemAction] { ItemAction.urlActions }
}

@MainActor
final class WebSearchProvider: ResultProvider {
    nonisolated let id = "web"
    nonisolated let declaredActions = ItemAction.urlActions
    /// Above ordinary prefix matches (~50–80) but below an exact app name (~100+), so
    /// "draw.io" still opens the app and "github.com/x" opens the browser.
    static let openScore = 85.0

    var settings = Config.WebSearch()
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard settings.enabled, let url = WebQuery.url(from: query.text) else { return [] }
        return [ScoredItem(item: WebAddressItem(text: query.text, url: url), score: Self.openScore, provider: self)]
    }

    func fallbackResults(for query: Query) -> [ScoredItem] {
        guard settings.enabled, !query.isEmpty else { return [] }
        return [ScoredItem(item: WebSearchItem(text: query.text, engine: settings.engine), score: 0, provider: self)]
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        let url = (item as? WebAddressItem)?.url ?? (item as? WebSearchItem)?.url
        guard let url else { NSSound.beep(); return }
        switch action.id {
        case "open":
            dismiss?()
            NSWorkspace.shared.open(url)
        case "copyURL": url.absoluteString.copyToPasteboard(toast: "URL copied")
        default: NSSound.beep()
        }
    }
}
