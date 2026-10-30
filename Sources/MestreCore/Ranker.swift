import Foundation

public enum Ranker {
    /// Where the best match came from.
    public enum MatchSource: Equatable, Sendable {
        case title
        /// A keyword such as the bundle identifier; not worth explaining to the user.
        case keyword
        /// A user alias; shown as the match reason.
        case alias(String)
    }

    public struct Match: Equatable {
        public let score: Double
        public let source: MatchSource
    }

    /// An alias typed exactly is the strongest signal there is: it beats an exact title.
    public static let exactAliasBonus = 60.0
    /// A keyword or alias only displaces the title when it is clearly better, otherwise
    /// short aliases would claim ordinary prefix matches ("f" → "alias ff").
    static let keywordMargin = 5.0

    /// Best fuzzy score of `query` against an item's title, its keywords and its aliases.
    /// `lowercasedQuery` must be `query.lowercased()`, computed once per keystroke.
    public static func score(_ item: some SearchItem, query: String, lowercasedQuery: String, aliases: [String] = []) -> Match? {
        var best = FuzzyMatcher.match(query, in: item.title).map { Match(score: $0.score, source: .title) }
        func consider(_ score: Double, _ source: MatchSource) {
            guard let current = best else { best = Match(score: score, source: source); return }
            let margin = current.source == .title ? keywordMargin : 0
            if score > current.score + margin { best = Match(score: score, source: source) }
        }
        for keyword in item.keywords {
            if let score = FuzzyMatcher.match(query, in: keyword)?.score { consider(score, .keyword) }
        }
        for alias in aliases {
            guard var score = FuzzyMatcher.match(query, in: alias)?.score else { continue }
            if alias.lowercased() == lowercasedQuery { score += exactAliasBonus }
            consider(score, .alias(alias))
        }
        return best
    }

    private struct Candidate<Item: SearchItem> {
        let item: Item
        let score: Double
        let source: MatchSource
    }

    /// Fuzzy-matches `items`, adds `boost`, and returns the top `limit` as results of `provider`.
    /// `aliases` supplies per-item user aliases. Generic over the item type so nothing
    /// is boxed until the final few results.
    public static func rank<Item: SearchItem>(
        _ items: [Item],
        query: String,
        limit: Int,
        provider: any ResultProvider,
        aliases: (Item) -> [String] = { _ in [] },
        boost: (Item) -> Double = { _ in 0 }
    ) -> [ScoredItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowercased = trimmed.lowercased()
        var candidates: [Candidate<Item>] = []
        for item in items {
            guard let match = score(item, query: trimmed, lowercasedQuery: lowercased, aliases: aliases(item)) else { continue }
            candidates.append(Candidate(item: item, score: match.score + boost(item), source: match.source))
        }
        return top(candidates, limit: limit, provider: provider)
    }

    /// Items with a positive `boost` (launch history), highest first. Shown while the query is empty.
    public static func recents<Item: SearchItem>(
        _ items: [Item],
        limit: Int,
        provider: any ResultProvider,
        boost: (Item) -> Double
    ) -> [ScoredItem] {
        var candidates: [Candidate<Item>] = []
        for item in items {
            let value = boost(item)
            if value > 0 { candidates.append(Candidate(item: item, score: value, source: .title)) }
        }
        return top(candidates, limit: limit, provider: provider)
    }

    private static func top<Item: SearchItem>(_ candidates: [Candidate<Item>], limit: Int, provider: any ResultProvider) -> [ScoredItem] {
        var sorted = candidates
        sorted.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.item.title.localizedCaseInsensitiveCompare(b.item.title) == .orderedAscending
        }
        return sorted.prefix(limit).map { candidate in
            let alias: String? = if case .alias(let alias) = candidate.source { alias } else { nil }
            return ScoredItem(item: candidate.item, score: candidate.score, provider: provider, alias: alias)
        }
    }
}
