import CoreServices
import Foundation

/// Looks words up in the system Dictionary (the same data Dictionary.app shows).
public enum WordLookup {
    /// Raw definition text for a term, nil when no dictionary has it.
    public static func definition(of term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let range = CFRange(location: 0, length: (trimmed as NSString).length)
        guard let text = DCSCopyTextDefinition(nil, trimmed as CFString, range)?.takeRetainedValue() as String? else { return nil }
        return text.isEmpty ? nil : text
    }

    /// Splits the dictionary's run-on text into display lines: headword, then each sense.
    /// "serendipity | ˌserənˈdipədē | noun the occurrence…" → ["serendipity | ˌserənˈdipədē |", "noun the occurrence…"]
    public static func lines(from definition: String, limit: Int = 6) -> [String] {
        var parts = definition
            .replacingOccurrences(of: "\u{2022}", with: "\n•")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // "word | prəˌnʌnsiˈeɪʃən | sense…": headword and pronunciation stay together, the
        // first sense starts after the second pipe. Entries with fewer pipes stay whole.
        if let first = parts.first {
            let pipes = first.indices.filter { first[$0] == "|" }
            if pipes.count >= 2 {
                let cut = pipes[1]
                let head = String(first[...cut]).trimmingCharacters(in: .whitespaces)
                let rest = String(first[first.index(after: cut)...]).trimmingCharacters(in: .whitespaces)
                parts = [head] + (rest.isEmpty ? [] : [rest]) + parts.dropFirst()
            }
        }
        return Array(parts.prefix(limit))
    }

    /// The dict:// URL that opens the term in Dictionary.app.
    public static func appURL(for term: String) -> URL? {
        term.trimmingCharacters(in: .whitespaces).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "dict://\($0)") }
    }
}
