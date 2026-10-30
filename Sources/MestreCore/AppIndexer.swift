import AppKit

/// Finds .app bundles by walking the standard application folders.
/// A plain directory scan is fast enough (a few hundred apps in well under a second)
/// and, unlike NSMetadataQuery, works even when Spotlight indexing is disabled.
public enum AppIndexer {
    public static let defaultDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        // Safari and a few other system apps live in the cryptex on recent macOS.
        URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications"),
    ]

    public struct ScanResult: Sendable {
        public var entries: [AppEntry] = []
        /// The roots and their non-bundle subfolders within depth: watching these
        /// catches every install, removal or rename the scan would notice.
        public var watchedDirectories: [URL] = []
    }

    /// Scans `directories` up to `maxDepth` levels deep (depth 2 reaches /Applications/Utilities)
    /// in a single walk. Safe to call off the main thread.
    public static func scan(directories: [URL] = defaultDirectories, maxDepth: Int = 2) -> ScanResult {
        let fileManager = FileManager.default
        var seen = Set<String>()
        var result = ScanResult()

        for directory in directories {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            result.watchedDirectories.append(directory)
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                if enumerator.level > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension == "app" else {
                    if enumerator.level < maxDepth,
                       (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        result.watchedDirectories.append(url)
                    }
                    continue
                }
                enumerator.skipDescendants()

                let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
                // The same app can be reachable through several paths (symlinks, cryptex mirrors);
                // the bundle identifier is the stable identity.
                let identity = bundleIdentifier ?? url.resolvingSymlinksInPath().path
                guard seen.insert(identity).inserted else { continue }

                var name = fileManager.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name.removeLast(4) }

                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)

                result.entries.append(AppEntry(name: name, url: url, bundleIdentifier: bundleIdentifier, icon: icon))
            }
        }

        result.entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return result
    }
}
