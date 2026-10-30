import Foundation

/// Turns "~/Doc" into the folder to list and the prefix to filter by, and filters a
/// folder listing the way a shell completion does.
public enum PathCompletion {
    public struct Target: Equatable {
        /// Absolute path of the folder to list.
        public let directory: String
        /// Lowercased name prefix typed after the last slash ("" lists everything).
        public let prefix: String
        /// The text as typed up to and including the last slash, for rebuilding the query.
        public let typedDirectory: String
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        /// A real folder to step into; packages (.app, .bundle) are not.
        public let isDirectory: Bool
    }

    /// True for text that is a path: "/…", "~/…" or a bare "~". "~bob" is not.
    public static func isPath(_ text: String) -> Bool {
        text == "~" || text.hasPrefix("~/") || text.hasPrefix("/")
    }

    public static func target(for text: String, home: String = NSHomeDirectory()) -> Target? {
        guard isPath(text) else { return nil }
        let normalized = text == "~" ? "~/" : text
        let slash = normalized.lastIndex(of: "/")!
        let typedDirectory = String(normalized[...slash])
        let prefix = String(normalized[normalized.index(after: slash)...]).lowercased()
        var directory = typedDirectory.hasPrefix("~") ? home + typedDirectory.dropFirst() : typedDirectory
        if directory.count > 1, directory.hasSuffix("/") { directory.removeLast() }
        return Target(directory: directory, prefix: prefix, typedDirectory: typedDirectory)
    }

    /// Reads a folder once: names plus folder/package flags from the same directory pass,
    /// sorted folders first. Disk I/O: call it off the main thread and cache the result.
    public static func list(_ directory: String) -> [Entry] {
        let url = URL(fileURLWithPath: directory)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: []) else {
            return []
        }
        var entries: [Entry] = []
        for item in contents {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
            entries.append(Entry(name: item.lastPathComponent, isDirectory: isDirectory))
        }
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// In-memory filter of a sorted listing: by prefix, hiding dot files unless asked for.
    public static func filter(_ entries: [Entry], prefix: String, showHidden: Bool, limit: Int) -> [Entry] {
        let hiddenOK = showHidden || prefix.hasPrefix(".")
        var result: [Entry] = []
        for entry in entries where hiddenOK || !entry.name.hasPrefix(".") {
            guard prefix.isEmpty || entry.name.lowercased().hasPrefix(prefix) else { continue }
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }
}
