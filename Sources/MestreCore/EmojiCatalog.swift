import Foundation

/// An emoji or typographic symbol with searchable words.
public struct EmojiEntry: Codable, Equatable, Sendable, Identifiable {
    public let character: String
    public let name: String
    public let keywords: [String]
    public let group: String  // "emoji" or "symbol"

    public var id: String { character }

    enum CodingKeys: String, CodingKey { case character = "c", name = "n", keywords = "k", group = "g" }
}

/// The bundled emoji and symbol list with search words precomputed, so a keystroke
/// compares prefixes against ready-made lowercase strings and allocates nothing per entry.
public struct EmojiCatalog: Sendable {
    public let entries: [EmojiEntry]
    private let words: [[String]]          // per entry: lowercased keywords + name words
    private let exact: [Set<String>]       // per entry: keywords, for exact hits
    private let byCharacter: [String: Int]

    public init(entries: [EmojiEntry]) {
        self.entries = entries
        words = entries.map { entry in entry.keywords.map { $0.lowercased() } + entry.name.lowercased().split(separator: " ").map(String.init) }
        exact = entries.map { Set($0.keywords.map { $0.lowercased() }) }
        byCharacter = Dictionary(entries.enumerated().map { ($0.element.character, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    public var isEmpty: Bool { entries.isEmpty }

    public func entry(for character: String) -> EmojiEntry? {
        byCharacter[character].map { entries[$0] }
    }

    /// Reads emoji.json. Decodes ~1 800 entries: call it off the main thread.
    public static func bundled() -> EmojiCatalog? {
        guard let url = BundledResource.url(forResource: "emoji", withExtension: "json"), let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([EmojiEntry].self, from: data) else { return nil }
        return EmojiCatalog(entries: entries)
    }

    /// Word-based search: every query word must match the start of a name or keyword word.
    /// Exact keyword hits rank first, then shorter names, then catalog order (the common
    /// emoji come first in the file).
    public func search(_ query: String, limit: Int) -> [EmojiEntry] {
        let needles = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !needles.isEmpty else { return Array(entries.prefix(limit)) }
        var scored: [(index: Int, score: Int)] = []
        for index in entries.indices {
            var score = 0
            for needle in needles {
                if exact[index].contains(needle) { score += 3 }
                else if words[index].contains(where: { $0.hasPrefix(needle) }) { score += 1 }
                else { score = 0; break }
            }
            if score > 0 { scored.append((index, score * 1000 - entries[index].name.count)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }.prefix(limit).map { entries[$0.index] }
    }

    /// `recent` first (those still in the catalog), then the rest in catalog order.
    public func recentsFirst(_ recent: [String], limit: Int) -> [EmojiEntry] {
        var result = recent.compactMap(entry(for:))
        let used = Set(result.map(\.character))
        for entry in entries where result.count < limit && !used.contains(entry.character) { result.append(entry) }
        return Array(result.prefix(limit))
    }
}

/// A bounded most-recent-first list of strings persisted in UserDefaults (usage data).
public final class RecentList {
    private let defaults: UserDefaults
    private let key: String
    public private(set) var items: [String]
    public var limit: Int {
        didSet { trim() }
    }

    public init(key: String, limit: Int, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
        items = Array((defaults.stringArray(forKey: key) ?? []).prefix(limit))
    }

    public func touch(_ item: String) {
        items.removeAll { $0 == item }
        items.insert(item, at: 0)
        trim()
    }

    private func trim() {
        if items.count > limit { items = Array(items.prefix(limit)) }
        defaults.set(items, forKey: key)
    }
}
