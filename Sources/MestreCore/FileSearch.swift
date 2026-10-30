import Foundation

/// Builds the Spotlight predicate for a file-name search: every word must appear in
/// the name (case- and diacritic-insensitive), hidden files and excluded folders are
/// left out by Spotlight itself, so the result cap never swallows the good hits.
public enum FileSearch {
    public static func predicate(for text: String, minimumLength: Int = 2, excludedFolders: [String] = []) -> NSPredicate? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.joined().count >= minimumLength else { return nil }
        var parts = words.map { NSPredicate(format: "kMDItemFSName CONTAINS[cd] %@", $0) }
        parts.append(NSPredicate(format: "NOT kMDItemFSName BEGINSWITH %@", "."))
        for folder in excludedFolders.map(standardized) {
            parts.append(NSPredicate(format: "NOT kMDItemPath BEGINSWITH[c] %@", folder + "/"))
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    /// Expands "~" and resolves symlinks the way Spotlight reports paths (/tmp → /private/tmp;
    /// Foundation's own resolver hides that prefix, so this uses realpath).
    public static func standardized(_ path: String) -> String {
        let expanded = NSString(string: path).expandingTildeInPath
        var resolved = expanded
        if let real = realpath(expanded, nil) {
            resolved = String(cString: real)
            free(real)
        }
        return resolved.count > 1 && resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }

    /// "/Users/me/Documents/x.pdf" → "~/Documents".
    public static func folderDescription(of path: String, home: String = NSHomeDirectory()) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        if folder == home { return "~" }
        return folder.hasPrefix(home + "/") ? "~" + folder.dropFirst(home.count) : folder
    }
}
