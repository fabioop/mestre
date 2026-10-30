import AppKit
import MestreCore

struct SnippetItem: SearchItem {
    let snippet: Snippet
    let keywords: [String]
    let subtitle: String?

    init(snippet: Snippet) {
        self.snippet = snippet
        keywords = snippet.keyword.map { [$0] } ?? []
        let preview = snippet.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        subtitle = [snippet.keyword, preview.nilIfEmpty].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    var id: String { snippet.id }
    var title: String { snippet.name }
    var icon: NSImage? { nil }
    var iconSymbol: String? { "text.quote" }
    var kind: ItemKind { .snippet }
    var actions: [ItemAction] { .pasteOrCopy() }
}

/// Snippets from config, ranked by name and keyword. Return expands the placeholders
/// and pastes into the app you came from; the caret lands at `{cursor}`.
@MainActor
final class SnippetProvider: ResultProvider {
    nonisolated let id = "snippets"
    nonisolated let declaredActions = ItemAction.pasteAndCopy

    var settings = Config.Snippets() {
        didSet { items = settings.enabled ? settings.items.map(SnippetItem.init) : [] }
    }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    /// Shared with the clipboard provider so snippets never enter the history.
    var paster: Paster?

    /// The snippet's text with placeholders filled from the current clipboard and formats.
    static func expansion(of snippet: Snippet, with settings: Config.Snippets) -> SnippetExpander.Expansion {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        return SnippetExpander.expand(snippet.text, clipboard: clipboard, dateFormat: settings.dateFormat, timeFormat: settings.timeFormat)
    }

    private var items: [SnippetItem] = []

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard !query.isEmpty, !items.isEmpty else { return [] }
        return Ranker.rank(items, query: query.text, limit: limit, provider: self)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let snippet = (item as? SnippetItem)?.snippet, let paster else { return }
        let expansion = Self.expansion(of: snippet, with: settings)
        switch action.id {
        case "paste":
            paster.paste(expansion.text, caretMoves: expansion.cursorOffsetFromEnd, dismiss: dismiss)
        case "copy":
            paster.copy(expansion.text, dismiss: dismiss)
        default: NSSound.beep()
        }
    }
}
