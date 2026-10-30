import Foundation

/// Decides what a free-text query means on the web: an address to open, or words to search.
public enum WebQuery {
    /// A URL when the text looks like one ("example.com", "localhost:8080/x", "https://…").
    /// Cheap on the keystroke path: text without a dot or scheme returns at once.
    public static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("@") else { return nil }
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()), url.host != nil else { return nil }
            return url
        }
        let lowercased = trimmed.lowercased()
        guard lowercased.contains(".") || lowercased.hasPrefix("localhost") else { return nil }

        // Host is everything before the first "/", "?", "#" or ":".
        let hostEnd = lowercased.firstIndex { "/?#:".contains($0) } ?? lowercased.endIndex
        let host = String(lowercased[..<hostEnd])
        guard !host.isEmpty, !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return nil }

        let isLocal = host == "localhost" || host.hasSuffix(".local") || isIPv4(host)
        let topLevel = host.split(separator: ".").last.map(String.init) ?? ""
        guard isLocal || host.hasPrefix("www.") || topLevelDomains.contains(topLevel) else { return nil }
        // Dev servers are plain HTTP; everything else gets TLS.
        let scheme = isLocal || host.hasPrefix("192.168.") || host.hasPrefix("10.") ? "http://" : "https://"
        return URL(string: scheme + trimmed)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    /// Common top-level domains, minus the ones that double as file extensions
    /// (sh, rs, pl, cc, app…), so "install.sh" and "Safari.app" stay searches.
    static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "dev", "co", "ai", "xyz", "info", "biz", "tv", "gg", "ly", "fm", "edu", "gov", "mil",
        "int", "eu", "pt", "br", "uk", "de", "fr", "es", "nl", "ch", "se", "no", "dk", "fi", "ru", "jp", "cn", "au", "ca",
        "us", "ie", "be", "at", "cz", "gr", "tr", "mx", "ar", "cl", "nz", "za", "kr", "tw", "hk", "sg", "ro", "hu", "ua",
        "il", "ae", "page", "site", "tech", "cloud", "design", "studio", "store", "blog", "news", "art", "games", "zone",
        "wiki", "live", "social", "email", "chat", "video", "music", "world", "today", "online", "digital",
    ]

    /// The search engine URL with the query filled in.
    public static func searchURL(engine: String, query: String) -> URL? {
        Quicklink.resolve(template: engine, query: query)
    }
}
