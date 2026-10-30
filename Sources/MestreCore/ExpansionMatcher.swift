import Foundation

/// Decides when recently typed text should expand into a snippet. Keeps only the
/// last few characters (never more than the longest keyword plus one) and is never
/// persisted. A keyword fires when the text ends with it and the character before it
/// is a word boundary, so "addr" inside "paddress" stays put.
public struct ExpansionMatcher: Equatable, Sendable {
    public static let minimumKeywordLength = 2

    /// Snippets by their keyword's last character: most keystrokes need no lookup at all.
    private let byLastCharacter: [Character: [Snippet]]
    private let maxLength: Int
    public private(set) var buffer = ""

    public init(snippets: [Snippet]) {
        var table: [Character: [Snippet]] = [:]
        var seen = Set<String>()
        for snippet in snippets {
            guard let keyword = snippet.keyword, keyword.count >= Self.minimumKeywordLength,
                  !keyword.contains(where: \.isWhitespace), seen.insert(keyword).inserted, let last = keyword.last else { continue }
            table[last, default: []].append(snippet)
        }
        byLastCharacter = table
        maxLength = table.values.flatMap { $0 }.compactMap { $0.keyword?.count }.max() ?? 0
    }

    public var isEmpty: Bool { byLastCharacter.isEmpty }

    /// Feeds typed characters. Returns the snippet whose keyword the text now ends with.
    public mutating func typed(_ text: String) -> Snippet? {
        guard maxLength > 0 else { return nil }
        buffer += text
        if buffer.count > maxLength + 1 { buffer = String(buffer.suffix(maxLength + 1)) }
        guard let last = buffer.last, let candidates = byLastCharacter[last] else { return nil }
        for snippet in candidates {
            guard let keyword = snippet.keyword, buffer.hasSuffix(keyword) else { continue }
            let before = buffer.dropLast(keyword.count).last
            if before == nil || before!.isWhitespace || before!.isPunctuation || before!.isSymbol {
                buffer = ""
                return snippet
            }
        }
        return nil
    }

    /// Backspace: forget the last character.
    public mutating func deletedBackward() {
        if !buffer.isEmpty { buffer.removeLast() }
    }

    /// Anything that moves the caret or switches context.
    public mutating func reset() { buffer = "" }
}
