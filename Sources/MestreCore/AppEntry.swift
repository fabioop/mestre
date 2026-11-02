import AppKit

/// One launchable application found on disk.
// NSImage is reference-typed but never mutated after indexing, so crossing threads is safe.
public struct AppEntry: Identifiable, Hashable, SearchItem, @unchecked Sendable {
    public let name: String
    public let url: URL
    public let bundleIdentifier: String?
    public let icon: NSImage?
    /// One of Apple's built-in apps: it lives under /System, not in a folder the user installs to.
    public let isSystemApp: Bool
    /// The bundle identifier without what nearly every app shares: its leading domain ("com.",
    /// "org.") and, on all the built-in apps, "apple." ("ca" isn't "com.apple.Home"). Unanchored,
    /// because an identifier isn't a name: "sa" is Safari, not "sandisk.installer".
    public let keywords: [String]
    public let id: String
    /// The path a running copy reports. Resolved here, off the main thread, because the
    /// running check reads it per app per keystroke.
    public let resolvedPath: String

    public var title: String { name }
    public var subtitle: String? { locationDescription }
    public var kind: ItemKind { .app }

    public init(name: String, url: URL, bundleIdentifier: String?, icon: NSImage?) {
        self.name = name
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        id = url.path
        resolvedPath = url.resolvingSymlinksInPath().path
        isSystemApp = id.hasPrefix("/System/")
        let parts = (bundleIdentifier ?? "").split(separator: ".").dropFirst()
        let keyword = (parts.first == "apple" ? parts.dropFirst() : parts).joined(separator: ".")
        keywords = keyword.isEmpty ? [] : [FuzzyMatcher.unanchored(keyword)]
    }

    /// The name the Finder shows for an app bundle, without its extension.
    public static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
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
