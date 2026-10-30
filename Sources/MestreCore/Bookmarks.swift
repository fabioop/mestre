import Foundation
import SQLite3

/// A browser bookmark and where it came from.
public struct Bookmark: Equatable, Sendable, Identifiable {
    public let title: String
    public let url: String
    /// Folder path inside the browser ("Bookmarks Bar / Work").
    public let folder: String
    public let browser: Browser
    public let profile: String
    public let host: String

    /// Unique even when the same link is bookmarked twice (two folders, two profiles).
    public var id: String { "\(browser.rawValue)|\(profile)|\(folder)|\(url)|\(title)" }

    public init(title: String, url: String, folder: String, browser: Browser, profile: String = "Default") {
        self.title = title
        self.url = url
        self.folder = folder
        self.browser = browser
        self.profile = profile
        host = URL(string: url)?.host ?? ""
    }
}

/// Browsers whose bookmark files are readable without Full Disk Access (Safari's are not).
public enum Browser: String, CaseIterable, Sendable {
    case chrome, brave, edge, chromium, vivaldi, arc, firefox

    public var name: String {
        switch self {
        case .chrome: return "Chrome"
        case .brave: return "Brave"
        case .edge: return "Edge"
        case .chromium: return "Chromium"
        case .vivaldi: return "Vivaldi"
        case .arc: return "Arc"
        case .firefox: return "Firefox"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .chromium: return "org.chromium.Chromium"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .arc: return "company.thebrowser.Browser"
        case .firefox: return "org.mozilla.firefox"
        }
    }

    /// Where this browser keeps profiles, under ~/Library/Application Support.
    var supportFolder: String {
        switch self {
        case .chrome: return "Google/Chrome"
        case .brave: return "BraveSoftware/Brave-Browser"
        case .edge: return "Microsoft Edge"
        case .chromium: return "Chromium"
        case .vivaldi: return "Vivaldi"
        case .arc: return "Arc/User Data"
        case .firefox: return "Firefox/Profiles"
        }
    }
}

/// One bookmark file: a Chromium profile's `Bookmarks` JSON or a Firefox `places.sqlite`.
public struct BookmarkSource: Equatable, Sendable {
    public let browser: Browser
    public let file: URL
    /// Profile folder name ("Default", "Profile 2", "abc.default-release").
    public let profile: String

    public init(browser: Browser, file: URL, profile: String) {
        self.browser = browser
        self.file = file
        self.profile = profile
    }

    /// Disk I/O: call it off the main thread.
    public func read() -> [Bookmark] {
        browser == .firefox ? FirefoxBookmarks.read(file, browser: browser, profile: profile) : ChromiumBookmarks.read(file, browser: browser, profile: profile)
    }

    /// Modification date and size, enough to tell whether a reload is worth doing.
    public var fingerprint: String {
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)"
    }
}

public enum Bookmarks {
    /// Bookmark files present on this Mac.
    public static func sources(applicationSupport: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) -> [BookmarkSource] {
        let fileManager = FileManager.default
        var result: [BookmarkSource] = []
        for browser in Browser.allCases {
            let base = applicationSupport.appendingPathComponent(browser.supportFolder)
            guard let profiles = try? fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { continue }
            for profile in profiles {
                let name = profile.lastPathComponent
                let file: URL
                if browser == .firefox {
                    file = profile.appendingPathComponent("places.sqlite")
                } else {
                    guard name == "Default" || name.hasPrefix("Profile ") else { continue }
                    file = profile.appendingPathComponent("Bookmarks")
                }
                if fileManager.fileExists(atPath: file.path) { result.append(BookmarkSource(browser: browser, file: file, profile: name)) }
            }
        }
        return result
    }
}

public enum ChromiumBookmarks {
    public static func read(_ file: URL, browser: Browser, profile: String = "Default") -> [Bookmark] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return parse(data, browser: browser, profile: profile)
    }

    /// Walks the `roots` tree of a Chromium Bookmarks file.
    public static func parse(_ data: Data, browser: Browser, profile: String = "Default") -> [Bookmark] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["roots"] as? [String: Any] else { return [] }
        var result: [Bookmark] = []
        for key in ["bookmark_bar", "other", "synced"] {
            guard let root = roots[key] as? [String: Any] else { continue }
            walk(root, path: [], browser: browser, profile: profile, into: &result)
        }
        return result
    }

    private static func walk(_ node: [String: Any], path: [String], browser: Browser, profile: String, into result: inout [Bookmark]) {
        let name = node["name"] as? String ?? ""
        if node["type"] as? String == "url", let url = node["url"] as? String {
            result.append(Bookmark(title: name.isEmpty ? url : name, url: url, folder: path.joined(separator: " / "), browser: browser, profile: profile))
            return
        }
        for child in node["children"] as? [[String: Any]] ?? [] {
            walk(child, path: path + [name], browser: browser, profile: profile, into: &result)
        }
    }
}

public enum FirefoxBookmarks {
    /// Opens the live database read-only and immutable: no copy, no lock, and the WAL
    /// contents Firefox hasn't checkpointed yet are still seen consistently.
    public static func read(_ file: URL, browser: Browser, profile: String = "default") -> [Bookmark] {
        guard let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return [] }
        return query(uri: "file:\(encoded)?mode=ro&immutable=1", browser: browser, profile: profile)
    }

    public static func query(uri: String, browser: Browser, profile: String = "default") -> [Bookmark] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }
        // type 1 = bookmark; rows under the tags root are tag assignments, not bookmarks.
        let sql = """
        SELECT b.title, p.url, COALESCE(f.title, '') FROM moz_bookmarks b
        JOIN moz_places p ON p.id = b.fk
        LEFT JOIN moz_bookmarks f ON f.id = b.parent
        WHERE b.type = 1 AND p.url NOT LIKE 'place:%'
          AND COALESCE(f.parent, -1) NOT IN (SELECT id FROM moz_bookmarks WHERE guid = 'tags________')
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [Bookmark] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let title = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
            guard let urlC = sqlite3_column_text(statement, 1) else { continue }
            let url = String(cString: urlC)
            let folder = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            result.append(Bookmark(title: title.isEmpty ? url : title, url: url, folder: folder, browser: browser, profile: profile))
        }
        return result
    }
}
