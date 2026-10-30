import Foundation

/// A saved link. With a `{query}` placeholder it becomes a search: typing the
/// keyword (or the name) followed by text fills the placeholder.
public struct Quicklink: Codable, Equatable, Sendable, Identifiable {
    public static let placeholder = "{query}"

    public var name: String
    public var url: String
    /// Short trigger word, e.g. "gh". Optional; the name itself always works.
    public var keyword: String?

    public var id: String { name }
    public var takesQuery: Bool { url.contains(Self.placeholder) }

    public init(name: String, url: String, keyword: String? = nil) {
        self.name = name
        self.url = Self.normalizeURL(url)
        self.keyword = Self.normalizeKeyword(keyword)
    }

    /// Keywords are one lowercase word; anything else becomes nil rather than a dead trigger.
    static func normalizeKeyword(_ keyword: String?) -> String? {
        keyword?.split(whereSeparator: \.isWhitespace).first.map { String($0).lowercased() }
    }

    /// "github.com" is what people type; NSWorkspace needs a scheme. "mailto:" and friends
    /// already have one, and a path ("~/Docs", "/Applications/X.app") becomes a file URL.
    static func normalizeURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath).absoluteString
        }
        // "host:port" is not a scheme; "mailto:", "tel:+1", "x-apple.systempreferences:" are.
        let hasScheme = trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:(?![0-9]+(/|$))"#, options: .regularExpression) != nil
        return hasScheme ? trimmed : "https://" + trimmed
    }

    /// What the search field should contain to run this link with a query.
    public var completionPrefix: String { (keyword ?? name) + " " }

    /// The URL with `{query}` filled in and percent-encoded. Nil for an empty query on a search link.
    public func resolvedURL(query: String) -> URL? {
        takesQuery ? Self.resolve(template: url, query: query) : URL(string: url)
    }

    /// Fills `{query}` in any template, percent-encoded. Nil when the query is empty.
    public static func resolve(template: String, query: String) -> URL? {
        guard !query.isEmpty, let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: placeholder, with: encoded))
    }

    enum CodingKeys: String, CodingKey { case name, url, keyword }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        url = Self.normalizeURL(try c.decode(String.self, forKey: .url))
        keyword = Self.normalizeKeyword(try c.decodeIfPresent(String.self, forKey: .keyword))
    }
}

private extension CharacterSet {
    /// RFC 3986 unreserved characters: what a query value may contain unencoded.
    static let urlQueryValueAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
}
