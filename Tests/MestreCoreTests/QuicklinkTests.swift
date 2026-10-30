import Foundation
import Testing
@testable import MestreCore

@Suite struct QuicklinkTests {
    @Test func schemesAndPathsKeepTheirMeaning() {
        #expect(Quicklink(name: "m", url: "mailto:a@b.c").url == "mailto:a@b.c")
        #expect(Quicklink(name: "p", url: "/Applications/Safari.app").url == "file:///Applications/Safari.app")
        #expect(Quicklink(name: "h", url: "~/Docs").url.hasPrefix("file:///"))
        #expect(Quicklink(name: "w", url: "github.com").url == "https://github.com")
        #expect(Quicklink(name: "l", url: "localhost:3000").url == "https://localhost:3000")
    }

    @Test func fillsAndEncodesTheQuery() {
        let link = Quicklink(name: "GitHub", url: "https://github.com/search?q={query}", keyword: "GH")
        #expect(link.takesQuery)
        #expect(link.keyword == "gh")
        #expect(link.resolvedURL(query: "swift concurrency & actors")?.absoluteString == "https://github.com/search?q=swift%20concurrency%20%26%20actors")
        #expect(link.resolvedURL(query: "") == nil)
    }

    @Test func plainLinksIgnoreTheQuery() {
        let link = Quicklink(name: "Repo", url: "https://example.com/x")
        #expect(!link.takesQuery)
        #expect(link.resolvedURL(query: "anything")?.absoluteString == "https://example.com/x")
    }

    @Test func normalizesKeywordsAndSchemes() {
        #expect(Quicklink(name: "A", url: "github.com", keyword: "  My GH ").keyword == "my")
        #expect(Quicklink(name: "A", url: "github.com", keyword: "   ").keyword == nil)
        #expect(Quicklink(name: "A", url: " github.com ").url == "https://github.com")
        #expect(Quicklink(name: "Web Search", url: "https://x/{query}").completionPrefix == "Web Search ")
        #expect(Quicklink(name: "Web Search", url: "https://x/{query}", keyword: "w").completionPrefix == "w ")
    }

    @Test func encodesNonASCIIQueries() {
        let link = Quicklink(name: "S", url: "https://x/?q={query}")
        #expect(link.resolvedURL(query: "ação")?.absoluteString == "https://x/?q=a%C3%A7%C3%A3o")
    }

    @Test func decodesFromConfig() throws {
        let json = #"{"quicklinks": [{"name": "GitHub", "url": "https://github.com/search?q={query}", "keyword": "Gh"}, {"name": "Docs", "url": "https://docs.example"}]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.quicklinks.count == 2)
        #expect(config.quicklinks[0].keyword == "gh")
        #expect(config.quicklinks[1].keyword == nil)
        #expect(Config().quicklinks.isEmpty)
    }
}
