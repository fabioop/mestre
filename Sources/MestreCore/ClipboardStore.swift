import CryptoKit
import Foundation

/// One thing that was on the pasteboard.
public struct ClipboardEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case text, files, image }

    public let id: UUID
    public let kind: Kind
    /// The text itself, the file paths joined by newlines, or the image's file name
    /// (derived from its content hash, so the same image is one entry).
    public let content: String
    public let sourceApp: String?
    public var copiedAt: Date
    /// Lowercased head of the content, computed once so filtering never re-lowercases.
    public let searchText: String

    public static let searchLength = 400

    public init(id: UUID = UUID(), kind: Kind, content: String, sourceApp: String?, copiedAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.content = content
        self.sourceApp = sourceApp
        self.copiedAt = copiedAt
        searchText = String(content.prefix(Self.searchLength)).lowercased()
    }

    enum CodingKeys: String, CodingKey { case id, kind, content, sourceApp, copiedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), kind: try c.decode(Kind.self, forKey: .kind),
                  content: try c.decode(String.self, forKey: .content), sourceApp: try c.decodeIfPresent(String.self, forKey: .sourceApp),
                  copiedAt: try c.decode(Date.self, forKey: .copiedAt))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try c.encode(copiedAt, forKey: .copiedAt)
    }

    /// First non-empty line, collapsed, for the row title.
    public var preview: String {
        let line = content.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
    }

    public var lineCount: Int { content.split(whereSeparator: \.isNewline).count }

    /// File name for image data: same bytes, same name.
    public static func imageName(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".png"
    }
}

/// Clipboard history, newest first, bounded. Pure data: the pasteboard watcher and
/// persistence live in the app.
public struct ClipboardHistory: Codable, Equatable, Sendable {
    public private(set) var entries: [ClipboardEntry] = []

    public init(entries: [ClipboardEntry] = []) { self.entries = entries }

    /// Adds to the front. Something already in the history moves to the front instead of
    /// being duplicated. Returns the entry that was dropped off the end, if any.
    @discardableResult
    public mutating func add(_ entry: ClipboardEntry, limit: Int) -> ClipboardEntry? {
        if let index = entries.firstIndex(where: { $0.kind == entry.kind && $0.content == entry.content }) {
            touch(at: index, date: entry.copiedAt)
            return nil
        }
        entries.insert(entry, at: 0)
        guard entries.count > max(1, limit) else { return nil }
        return entries.removeLast()
    }

    /// Moves an entry to the front with a fresh timestamp (it was just used again).
    public mutating func touch(id: UUID, date: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        touch(at: index, date: date)
    }

    private mutating func touch(at index: Int, date: Date) {
        var entry = entries.remove(at: index)
        entry.copiedAt = date
        entries.insert(entry, at: 0)
    }

    public mutating func remove(id: UUID) -> ClipboardEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    public mutating func removeAll() -> [ClipboardEntry] {
        defer { entries = [] }
        return entries
    }

    /// Drops entries older than `maxAge` (0 keeps everything). Returns what was removed.
    public mutating func expire(olderThan maxAge: TimeInterval, now: Date = Date()) -> [ClipboardEntry] {
        guard maxAge > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-maxAge)
        let expired = entries.filter { $0.copiedAt < cutoff }
        entries.removeAll { $0.copiedAt < cutoff }
        return expired
    }

    /// Newest first; a non-empty query filters by content: substring hits first (cheap),
    /// then fuzzy matches to fill the remaining slots.
    public func matching(_ query: String, limit: Int) -> [ClipboardEntry] {
        guard !query.isEmpty else { return Array(entries.prefix(limit)) }
        let needle = query.lowercased()
        var hits = entries.filter { $0.searchText.contains(needle) }
        if hits.count < limit {
            let rest = entries.filter { !$0.searchText.contains(needle) }
            var scored: [(ClipboardEntry, Double)] = []
            for entry in rest {
                guard let match = FuzzyMatcher.match(needle, in: entry.searchText) else { continue }
                scored.append((entry, match.score))
            }
            hits += scored.sorted { $0.1 > $1.1 }.map(\.0)
        }
        return Array(hits.prefix(limit))
    }
}

/// The `enabled` + `keyword` pattern shared by keyword-mode providers ("kill x", "clip x").
public struct KeywordMode: Equatable, Sendable {
    public let enabled: Bool
    public let keyword: String

    public init(enabled: Bool, keyword: String) {
        self.enabled = enabled
        self.keyword = keyword
    }

    public func matches(_ query: Query) -> Bool { enabled && query.firstWord == keyword }
}

public extension ScoredItem {
    /// Items in a fixed order, all above fuzzy matches: a listing rather than a ranking.
    static func pinned(_ items: [any SearchItem], provider: any ResultProvider) -> [ScoredItem] {
        items.enumerated().map { ScoredItem(item: $0.element, score: pinnedScore - Double($0.offset), provider: provider) }
    }
}

public enum RelativeTime {
    /// "just now", "4 min ago", "2 h ago", "3 d ago", else a short date.
    public static func describe(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3600)) h ago"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400)) d ago"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}
