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
    /// Text read from an image entry (`ocr.clipboardImages`): nil until it has been read, empty
    /// when it had none, so each image is read once.
    public private(set) var recognizedText: String?
    /// Lowercased head of what this entry searches, computed once so filtering never
    /// re-lowercases: the content's first `searchLength` characters, or for an image with text,
    /// the first `recognizedSearchLength` characters of that text, precomposed like typed
    /// queries so the byte search in `contains` matches é with é. Fuzzy matching reads only
    /// its first `searchLength` characters.
    public private(set) var searchText: String

    public static let searchLength = 400
    public static let recognizedSearchLength = 4000

    public init(id: UUID = UUID(), kind: Kind, content: String, sourceApp: String?, copiedAt: Date = Date(), recognizedText: String? = nil) {
        self.id = id
        self.kind = kind
        self.content = content
        self.sourceApp = sourceApp
        self.copiedAt = copiedAt
        searchText = String(content.prefix(Self.searchLength)).lowercased()
        if kind == .image, recognizedText != nil { setRecognizedText(recognizedText) }
    }

    /// Stores what was read from the image and makes it searchable. Ignored for text and files.
    public mutating func setRecognizedText(_ text: String?) {
        guard kind == .image else { return }
        recognizedText = text
        searchText = hasRecognizedText
            ? String(text!.prefix(Self.recognizedSearchLength)).lowercased().precomposedStringWithCanonicalMapping
            : String(content.prefix(Self.searchLength)).lowercased()
    }

    /// An image whose text was read and had some.
    public var hasRecognizedText: Bool { recognizedText?.isEmpty == false }

    /// The image's text on one line, for the row's subtitle; built when a row renders.
    public var recognizedSnippet: String? {
        guard let text = recognizedText, !text.isEmpty else { return nil }
        return Self.collapsed(text.prefix(Self.searchLength), limit: 60)
    }

    /// What fuzzy matching runs on: the short head of `searchText`.
    var fuzzyText: String {
        hasRecognizedText ? String(searchText.prefix(Self.searchLength)) : searchText
    }

    /// Whether `needle` (lowercased, precomposed) is a substring of what this entry searches.
    func contains(_ needle: String) -> Bool {
        hasRecognizedText ? Self.bytes(searchText, contain: needle) : searchText.contains(needle)
    }

    /// Whitespace runs as single spaces, cut at `limit` characters with an ellipsis.
    static func collapsed(_ text: Substring, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    /// UTF-8 byte search: an order of magnitude faster than `contains` over 4 000 characters.
    /// Both sides are lowercased and Vision's output is precomposed, so bytes match as text does.
    static func bytes(_ haystack: String, contain needle: String) -> Bool {
        let found = haystack.utf8.withContiguousStorageIfAvailable { hay in
            needle.utf8.withContiguousStorageIfAvailable { pin in
                pin.isEmpty || memmem(hay.baseAddress, hay.count, pin.baseAddress, pin.count) != nil
            }
        }
        return (found ?? nil) ?? haystack.contains(needle)
    }

    /// `text` came later: older files have no such key and decode as not read yet.
    enum CodingKeys: String, CodingKey { case id, kind, content, sourceApp, copiedAt, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), kind: try c.decode(Kind.self, forKey: .kind),
                  content: try c.decode(String.self, forKey: .content), sourceApp: try c.decodeIfPresent(String.self, forKey: .sourceApp),
                  copiedAt: try c.decode(Date.self, forKey: .copiedAt), recognizedText: try c.decodeIfPresent(String.self, forKey: .text))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try c.encode(copiedAt, forKey: .copiedAt)
        try c.encodeIfPresent(recognizedText, forKey: .text)
    }

    /// First non-empty line, collapsed, for the row title.
    public var preview: String {
        // Bounded: this runs when the panel opens, and an entry can be a megabyte on one line.
        let line = content.prefix(Self.searchLength * 10).split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return Self.collapsed(line, limit: 120)
    }

    public var lineCount: Int { content.split(whereSeparator: \.isNewline).count }

    /// File name for image data: same bytes, same name.
    public static func imageName(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    /// True for a name `imageName(for:)` could have made, so an edited history can't name another file.
    public static func isImageName(_ name: String) -> Bool {
        name.range(of: #"^[0-9a-f]{64}\.png$"#, options: .regularExpression) != nil
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

    /// Names of the image entries whose text hasn't been read yet, newest first.
    public var imagesAwaitingText: [String] {
        entries.filter { $0.kind == .image && $0.recognizedText == nil }.map(\.content)
    }

    /// Stores the text read from the image named `name`. False when no entry has it any more.
    @discardableResult
    public mutating func setRecognizedText(_ text: String, forImage name: String) -> Bool {
        var found = false
        for index in entries.indices where entries[index].kind == .image && entries[index].content == name {
            entries[index].setRecognizedText(text)
            found = true
        }
        return found
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
        // Precomposed for the byte search over image text; `String.contains` doesn't mind either form.
        let needle = query.lowercased().precomposedStringWithCanonicalMapping
        // One substring pass; the misses are kept as indices, needed only when fuzzy runs.
        var hits: [ClipboardEntry] = []
        var misses: [Int] = []
        for (index, entry) in entries.enumerated() {
            if entry.contains(needle) { hits.append(entry) } else { misses.append(index) }
        }
        if hits.count < limit {
            let rest = misses.lazy.map { entries[$0] }
            var scored: [(ClipboardEntry, Double)] = []
            for entry in rest {
                guard let match = FuzzyMatcher.match(needle, in: entry.fuzzyText) else { continue }
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
    /// The keyword alone isn't enough; it needs the space after it. A short keyword ("cal",
    /// "tr") then never hides the apps whose names start with it.
    public let needsSpace: Bool

    public init(enabled: Bool, keyword: String, needsSpace: Bool = false) {
        self.enabled = enabled
        self.keyword = keyword
        self.needsSpace = needsSpace
    }

    public func matches(_ query: Query) -> Bool {
        enabled && query.firstWord == keyword && (!needsSpace || query.raw.drop { $0.isWhitespace }.count > keyword.count)
    }
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
