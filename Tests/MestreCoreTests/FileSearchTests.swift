import Foundation
import Testing
@testable import MestreCore

@Suite struct FileSearchTests {
    @Test func predicateRequiresEveryWordSkipsHiddenAndExcludedFolders() throws {
        let predicate = try #require(FileSearch.predicate(for: "Report 2024", excludedFolders: ["/tmp"]))
        let text = predicate.predicateFormat
        #expect(text.contains("kMDItemFSName CONTAINS[cd] \"Report\""))
        #expect(text.contains("kMDItemFSName CONTAINS[cd] \"2024\""))
        #expect(text.contains("NOT kMDItemFSName BEGINSWITH \".\""))
        #expect(text.contains("NOT kMDItemPath BEGINSWITH[c] \"/private/tmp/\""))
        #expect(FileSearch.predicate(for: "   ") == nil)
        #expect(FileSearch.predicate(for: "a", minimumLength: 2) == nil)
        #expect(FileSearch.predicate(for: "a b", minimumLength: 2) != nil)
    }

    @Test func standardizedPathsAndFolderDescription() {
        let home = "/Users/me"
        #expect(FileSearch.standardized("~/Library/").hasSuffix("/Library"))
        #expect(FileSearch.standardized("/tmp") == "/private/tmp")
        #expect(FileSearch.folderDescription(of: "/Users/me/Documents/x.pdf", home: home) == "~/Documents")
        #expect(FileSearch.folderDescription(of: "/Users/meX/x.pdf", home: home) == "/Users/meX")
        #expect(FileSearch.folderDescription(of: "/Users/me/x.pdf", home: home) == "~")
        #expect(FileSearch.folderDescription(of: "/tmp/x", home: home) == "/tmp")
    }

    @Test func filesConfigDecodesAndExpands() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"files": {"folders": ["~/Documents"], "maxResults": 500}}"#.utf8))
        #expect(config.files.folders == ["~/Documents"])
        #expect(config.files.maxResults == 100 && config.files.minimumLength == 2)
        #expect(Config().files.excludedFolders.contains("~/Library"))
    }
}
