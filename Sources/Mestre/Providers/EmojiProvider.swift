import AppKit
import MestreCore

struct EmojiItem: SearchItem {
    let entry: EmojiEntry
    let image: NSImage

    var id: String { entry.id }
    var title: String { entry.name }
    var subtitle: String? { entry.group == "symbol" ? "Symbol" : entry.keywords.prefix(4).joined(separator: ", ") }
    var icon: NSImage? { image }
    var kind: ItemKind { .emoji }
    var actions: [ItemAction] { .pasteOrCopy() }
}

/// ":fire" or "emoji fire" lists emoji and symbols; Return pastes the character.
/// Recently used ones come first on an empty query. The catalog loads in the
/// background at launch.
@MainActor
final class EmojiProvider: ResultProvider {
    nonisolated let id = "emoji"
    nonisolated let declaredActions = ItemAction.pasteAndCopy

    var settings = Config.Emoji() {
        didSet {
            mode = KeywordMode(enabled: settings.enabled, keyword: settings.keyword)
            recents.limit = settings.recentCount
        }
    }
    private var mode = KeywordMode(enabled: true, keyword: Config.Emoji().keyword)
    func owns(_ query: Query) -> Bool { searchText(in: query) != nil }
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    var paster: Paster?

    private var catalog = EmojiCatalog(entries: [])
    private let images = NSCache<NSString, NSImage>()
    private let recents = RecentList(key: "recentEmoji", limit: Config.Emoji().recentCount)

    init() {
        Task {
            guard let loaded = await Task.detached(priority: .utility, operation: { EmojiCatalog.bundled() }).value else { return }
            catalog = loaded
            onChange?()
        }
    }

    func homeFeature() -> HomeFeature? {
        guard settings.enabled else { return nil }
        return HomeFeature(id: "emoji", title: "Emoji & Symbols", subtitle: "\(settings.prefix)fire or \(settings.keyword) fire. Return pastes", symbol: "face.smiling", completion: settings.prefix)
    }

    func results(for query: Query, limit: Int) -> [ScoredItem] {
        guard let text = searchText(in: query), !catalog.isEmpty else { return [] }
        let entries = text.isEmpty ? catalog.recentsFirst(recents.items, limit: limit) : catalog.search(text, limit: limit)
        return ScoredItem.pinned(entries.map { EmojiItem(entry: $0, image: image(for: $0)) }, provider: self)
    }

    /// What to search for, if this query is for us: after the keyword or after the prefix.
    private func searchText(in query: Query) -> String? {
        if mode.matches(query) { return query.remainder }
        if settings.enabled, !settings.prefix.isEmpty, query.text.hasPrefix(settings.prefix) {
            return String(query.text.dropFirst(settings.prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func perform(_ action: ItemAction, on item: any SearchItem) {
        guard let entry = (item as? EmojiItem)?.entry, let paster else { return }
        recents.touch(entry.character)
        switch action.id {
        case "paste": paster.paste(entry.character, dismiss: dismiss)
        case "copy": paster.copy(entry.character, dismiss: dismiss)
        default: NSSound.beep()
        }
    }

    /// The character drawn as a 32pt image, cached: the row wants an icon, not text.
    private func image(for entry: EmojiEntry) -> NSImage {
        if let cached = images.object(forKey: entry.character as NSString) { return cached }
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: false) { rect in
            let text = NSAttributedString(string: entry.character, attributes: [.font: NSFont.systemFont(ofSize: 22)])
            let bounds = text.boundingRect(with: NSSize(width: 200, height: 200), options: .usesLineFragmentOrigin)
            text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
            return true
        }
        images.setObject(image, forKey: entry.character as NSString)
        return image
    }
}
