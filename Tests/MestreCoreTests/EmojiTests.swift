import Foundation
import Testing
@testable import MestreCore

@Suite struct EmojiCatalogTests {
    @Test func bundledCatalogLoadsAndSearches() throws {
        let catalog = try #require(EmojiCatalog.bundled())
        #expect(catalog.entries.count > 1500)
        #expect(catalog.search("fire", limit: 5).first?.character == "🔥")
        #expect(catalog.search("thumbs up", limit: 5).first?.character == "👍")
        #expect(catalog.search("right arrow", limit: 5).contains { $0.character == "→" })
        #expect(catalog.search("zzzzqq", limit: 5).isEmpty)
        #expect(catalog.search("", limit: 3).count == 3)
    }

    @Test func exactKeywordBeatsPrefixMatch() throws {
        let catalog = try #require(EmojiCatalog.bundled())
        #expect(catalog.search("heart", limit: 3).first?.character == "❤️")
    }

    @Test func recentsFirstThenCatalogOrder() throws {
        let catalog = try #require(EmojiCatalog.bundled())
        let list = catalog.recentsFirst(["🚀", "not-an-emoji", "🔥"], limit: 4)
        #expect(list.map(\.character).prefix(2) == ["🚀", "🔥"])
        #expect(list.count == 4)
    }

    @Test func recentListIsBoundedAndPersists() {
        let defaults = UserDefaults(suiteName: "RecentListTests-\(UUID().uuidString)")!
        let list = RecentList(key: "r", limit: 2, defaults: defaults)
        list.touch("a"); list.touch("b"); list.touch("a"); list.touch("c")
        #expect(list.items == ["c", "a"])
        #expect(RecentList(key: "r", limit: 2, defaults: defaults).items == ["c", "a"])
        list.limit = 1
        #expect(list.items == ["c"])
    }

    @Test func emojiConfigDecodes() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"emoji": {"prefix": "", "recentCount": 999}}"#.utf8))
        #expect(config.emoji.prefix == "" && config.emoji.recentCount == 200 && config.emoji.keyword == "emoji")
    }
}
