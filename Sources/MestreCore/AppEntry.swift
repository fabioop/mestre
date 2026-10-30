import AppKit

/// One launchable application found on disk.
// NSImage is reference-typed but never mutated after indexing, so crossing threads is safe.
public struct AppEntry: Identifiable, Hashable, SearchItem, @unchecked Sendable {
    public let name: String
    public let url: URL
    public let bundleIdentifier: String?
    public let icon: NSImage?

    public var id: String { url.path }
    public var title: String { name }
    public var subtitle: String? { locationDescription }
    public var kind: ItemKind { .app }
    public var keywords: [String] { bundleIdentifier.map { [$0] } ?? [] }

    public init(name: String, url: URL, bundleIdentifier: String?, icon: NSImage?) {
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
    }

    /// Folder the app lives in, with the home directory abbreviated: "/Applications", "~/Applications".
    public var locationDescription: String {
        var folder = url.deletingLastPathComponent().path
        // System apps live in a cryptex since macOS 13; the user knows them as /System/Applications.
        if folder.hasPrefix(Self.cryptexPrefix) { folder = String(folder.dropFirst(Self.cryptexPrefix.count)) }
        let home = NSHomeDirectory()
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    static let cryptexPrefix = "/System/Volumes/Preboot/Cryptexes/App"

    public static func == (lhs: AppEntry, rhs: AppEntry) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
