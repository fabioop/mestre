import Foundation
import Testing
@testable import MestreCore

@Suite struct WebQueryTests {
    @Test func recognisesAddresses() {
        #expect(WebQuery.url(from: "example.com")?.absoluteString == "https://example.com")
        #expect(WebQuery.url(from: "docs.swift.org/path?x=1")?.absoluteString == "https://docs.swift.org/path?x=1")
        #expect(WebQuery.url(from: "localhost:8080/app")?.absoluteString == "http://localhost:8080/app")
        #expect(WebQuery.url(from: "Localhost")?.absoluteString == "http://Localhost")
        #expect(WebQuery.url(from: "192.168.1.5:8080")?.absoluteString == "http://192.168.1.5:8080")
        #expect(WebQuery.url(from: "example.com?q=1")?.absoluteString == "https://example.com?q=1")
        #expect(WebQuery.url(from: "WWW.Foo.internal")?.absoluteString == "https://WWW.Foo.internal")
        #expect(WebQuery.url(from: "http://example.com")?.absoluteString == "http://example.com")
        #expect(WebQuery.url(from: "www.anything.internal")?.absoluteString == "https://www.anything.internal")
        #expect(WebQuery.url(from: "draw.io")?.absoluteString == "https://draw.io")
    }

    @Test func rejectsOrdinaryText() {
        for text in ["safari", "2.5", "hello world", "example.", ".com", "a.b.c.1", "file.txt", "ftp://x.y", "v1.2", "Package.swift",
                     "config.json", "install.sh", "main.rs", "Safari.app", "user@x.com", "https://", "x..com"] {
            #expect(WebQuery.url(from: text) == nil, "\(text) is not an address")
        }
    }

    @Test func buildsSearchURLs() {
        #expect(WebQuery.searchURL(engine: "https://duckduckgo.com/?q={query}", query: "swift actors")?.absoluteString == "https://duckduckgo.com/?q=swift%20actors")
        #expect(WebQuery.searchURL(engine: "https://duckduckgo.com/?q={query}", query: "") == nil)
    }

    @Test func engineMustHaveAPlaceholder() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"webSearch": {"engine": "https://google.com"}}"#.utf8))
        #expect(config.webSearch.engine == Config.WebSearch().engine)
    }

    @Test @MainActor func fallbackRowsAreAlwaysLast() {
        let provider = StubProvider()
        let ranked = (0..<10).map { ScoredItem(item: entry("App \($0)"), score: Double(100 - $0), provider: provider) }
        let fallback = [ScoredItem(item: entry("Search"), score: 0, provider: provider)]
        let merged = ResultMerger.merge([ranked], limit: 8, fallback: fallback)
        #expect(merged.count == 8)
        #expect(merged.last?.item.title == "Search")
        #expect(merged.first?.item.title == "App 0")
    }
}
