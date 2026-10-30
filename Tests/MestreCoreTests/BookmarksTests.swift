import Foundation
import SQLite3
import Testing
@testable import MestreCore

@Suite struct BookmarksTests {
    @Test func parsesChromiumTree() {
        let json = """
        {"roots": {"bookmark_bar": {"name": "Bookmarks Bar", "type": "folder", "children": [
            {"type": "url", "name": "Swift", "url": "https://swift.org/"},
            {"type": "folder", "name": "Work", "children": [{"type": "url", "name": "", "url": "https://example.com/x"}]}
        ]}, "other": {"name": "Other", "type": "folder", "children": []}}}
        """
        let bookmarks = ChromiumBookmarks.parse(Data(json.utf8), browser: .chrome)
        #expect(bookmarks.count == 2)
        #expect(bookmarks[0] == Bookmark(title: "Swift", url: "https://swift.org/", folder: "Bookmarks Bar", browser: .chrome))
        #expect(bookmarks[0].id != Bookmark(title: "Swift", url: "https://swift.org/", folder: "Other", browser: .chrome).id)
        #expect(bookmarks[1].title == "https://example.com/x" && bookmarks[1].folder == "Bookmarks Bar / Work")
        #expect(bookmarks[0].host == "swift.org")
        #expect(ChromiumBookmarks.parse(Data("nope".utf8), browser: .chrome).isEmpty)
    }

    @Test func readsAFirefoxPlacesDatabase() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("places-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: file) }
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        for sql in [
            "CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT)",
            "CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, title TEXT, guid TEXT)",
            "INSERT INTO moz_places VALUES (1, 'https://developer.apple.com/'), (2, 'place:type=6')",
            "INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 'Toolbar', 'toolbar_____'), (2, 1, 1, 1, 'Apple Developer', 'b1'), (3, 1, 2, 1, 'Recent', 'b2')",
            "INSERT INTO moz_bookmarks VALUES (4, 2, NULL, 0, 'Tags', 'tags________'), (5, 2, NULL, 4, 'swift', 't1'), (6, 1, 1, 5, NULL, 'tag-assign')",
        ] {
            #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        }
        sqlite3_close(db)
        let bookmarks = FirefoxBookmarks.read(file, browser: .firefox, profile: "p")
        #expect(bookmarks == [Bookmark(title: "Apple Developer", url: "https://developer.apple.com/", folder: "Toolbar", browser: .firefox, profile: "p")])
        #expect(!FileManager.default.fileExists(atPath: file.path + "-wal"), "read in place leaves no sidecar files")
    }

    @Test func discoversSourcesUnderApplicationSupport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("appsupport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        for path in ["Google/Chrome/Default", "Google/Chrome/Profile 2", "Google/Chrome/System Profile", "Firefox/Profiles/abc.default-release"] {
            try fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: root.appendingPathComponent("Google/Chrome/Default/Bookmarks").path, contents: Data())
        fm.createFile(atPath: root.appendingPathComponent("Google/Chrome/Profile 2/Bookmarks").path, contents: Data())
        fm.createFile(atPath: root.appendingPathComponent("Google/Chrome/System Profile/Bookmarks").path, contents: Data())
        fm.createFile(atPath: root.appendingPathComponent("Firefox/Profiles/abc.default-release/places.sqlite").path, contents: Data())
        let sources = Bookmarks.sources(applicationSupport: root)
        #expect(sources.count == 3)
        #expect(sources.filter { $0.browser == .chrome }.map(\.profile).sorted() == ["Default", "Profile 2"])
        #expect(sources.contains { $0.browser == .firefox && $0.profile == "abc.default-release" })
        #expect(sources.allSatisfy { !$0.fingerprint.isEmpty })
    }

    @Test func bookmarksConfigDecodes() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"bookmarks": {"excludeBrowsers": ["arc"], "searchEverywhere": true}}"#.utf8))
        #expect(config.bookmarks.excludeBrowsers == ["arc"] && config.bookmarks.searchEverywhere && config.bookmarks.keyword == "bm")
    }
}
