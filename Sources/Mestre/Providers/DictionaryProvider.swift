import AppKit
import MestreCore

struct DefinitionItem: SearchItem {
    let term: String
    let definition: String
    let line: String
    let index: Int

    var id: String { "\(term)#\(index)" }
    var title: String { line }
    var subtitle: String? { index == 0 ? "Dictionary" : nil }
    var icon: NSImage? { nil }
    var iconSymbol: String? { index == 0 ? "character.book.closed" : "text.alignleft" }
    var kind: ItemKind { .definition }
    var actions: [ItemAction] { Self.actions }

    static let actions = [
        ItemAction(id: "openDictionary", title: "Open in Dictionary", icon: "book"),
        ItemAction(id: "copy", title: "Copy Definition", icon: "doc.on.doc"),
    ]
}

/// "define serendipity" shows the system dictionary's entry, one sense per row, and so does a
/// single pasted word, above everything else.
/// A lookup costs ~20 ms, so it runs off the main thread after a short pause and the
/// rows arrive through onChange. Return opens Dictionary.app on the word.
@MainActor
final class DictionaryProvider: ResultProvider {
    nonisolated let id = "dictionary"
    nonisolated let declaredActions = DefinitionItem.actions

    var settings = Config.DictionaryLookup() {
        didSet { mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword) }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.DictionaryLookup().keyword)
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?

    private var pendingTerm = ""
    private var found: (term: String, definition: String, lines: [String], card: DictionaryEntry?)?
    private var pending: DispatchWorkItem?

    func owns(_ query: Query) -> Bool { mode.matches(query) }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "dictionary", title: "Define Word", subtitle: "The system dictionary. Return opens Dictionary", symbol: "character.book.closed", keyword: settings.keyword)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        let term: String
        if mode.matches(query), !query.remainder.isEmpty { term = query.remainder }
        else if let word = pastedWord(query) { term = word }
        else { return [] }
        if term != pendingTerm { lookUp(term) }
        guard let found, found.term == term else { return [] }
        let items = found.lines.prefix(min(limit, settings.maxLines)).enumerated().map { index, line in
            DefinitionItem(term: term, definition: found.definition, line: line, index: index)
        }
        return ScoredItem.pinned(items, provider: self)
    }

    private func pastedWord(_ query: Query) -> String? {
        guard settings.enabled, settings.onPaste, query.isPasted, query.words.count == 1, query.text.count >= 2,
              query.text.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" }) else { return nil }
        return query.text
    }

    /// The definition laid out as cards (`dictionary.cards`) when `item` is this lookup's row.
    func card(for item: any SearchItem) -> DictionaryEntry? {
        guard settings.cards, let item = item as? DefinitionItem, let found, found.term == item.term else { return nil }
        return found.card
    }

    func queryLeft() {
        pending?.cancel()
        pendingTerm = ""
        found = nil
    }

    private func lookUp(_ term: String) {
        pendingTerm = term
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let maxSenses = self.settings.cardSenses
            Task {
                let found = await Task.detached(priority: .userInitiated) {
                    WordLookup.definition(of: term).map { (term, $0, WordLookup.lines(from: $0, limit: 20), DictionaryEntry.parse($0, maxSenses: maxSenses)) }
                }.value
                guard self.pendingTerm == term else { return }
                self.found = found
                self.onChange?()
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.debounceSeconds, execute: work)
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let item = item as? DefinitionItem else { return }
        switch action.id {
        case "openDictionary":
            dismiss?()
            if let url = WordLookup.appURL(for: item.term) { NSWorkspace.shared.open(url) }
        case "copy":
            item.definition.copyToPasteboard()
            dismiss?()
        default: NSSound.beep()
        }
    }
}
