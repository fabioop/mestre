import Foundation

/// Two-letter keys for commands and features (S3): generated from the title, overridable in
/// `quickKeys`, shown as a cap on the row. Typing one exactly puts its row first.
public enum QuickKeys {
    /// `titles`: id → title for everything that gets a key. `overrides`: key → id from config.
    /// Returns id → key. A user key always wins; generated keys never collide with each
    /// other or with a user key, and an id with no free candidate gets none.
    public static func assign(titles: [(id: String, title: String)], overrides: [String: String]) -> [String: String] {
        var keys: [String: String] = [:]
        let known = Dictionary(titles.map { ($0.id.lowercased(), $0.id) }) { first, _ in first }
        // User keys first, in key order so two keys naming one id resolve the same way every time.
        for (key, target) in overrides.sorted(by: { $0.key < $1.key }) {
            if let id = known[target.lowercased()], keys[id] == nil { keys[id] = key.lowercased() }
        }
        var taken = Set(overrides.keys.map { $0.lowercased() })
        for (id, title) in titles where keys[id] == nil {
            guard let key = candidates(for: title).first(where: { !taken.contains($0) }) else { continue }
            keys[id] = key
            taken.insert(key)
        }
        return keys
    }

    /// Where a generated key's row goes in `rows`: first, except under computed answers and rows
    /// the text really names (an alias, or a title starting with it), so "sl" keeps Slack on top
    /// and never sleeps the Mac by surprise. A row weighted below zero doesn't count.
    public static func position(for query: String, in rows: [ScoredItem]) -> Int {
        let last = rows.lastIndex { row in
            row.score >= ScoredItem.pinnedScore || (row.score > 0 && (row.alias?.lowercased() == query || row.item.title.lowercased().hasPrefix(query)))
        }
        return last.map { $0 + 1 } ?? 0
    }

    /// Initials of the first two words ("Lock Screen" → "ls"), then the first letter with each
    /// following letter ("sl", "se", "sp" for "Sleep"), then the first two letters of the second word.
    static func candidates(for title: String) -> [String] {
        let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let first = words.first, let a = first.first else { return [] }
        var list: [String] = []
        if words.count > 1, let b = words[1].first { list.append("\(a)\(b)") }
        for c in first.dropFirst() where list.count < 6 { list.append("\(a)\(c)") }
        if words.count > 1, words[1].count > 1 { list.append(String(words[1].prefix(2))) }
        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }
}
