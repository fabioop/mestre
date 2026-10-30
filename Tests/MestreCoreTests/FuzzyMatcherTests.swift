import AppKit
import Testing
@testable import MestreCore

@Suite struct FuzzyMatcherTests {
    @Test func prefixBeatsScatteredMatch() throws {
        let prefix = try #require(FuzzyMatcher.match("saf", in: "Safari"))
        let scattered = try #require(FuzzyMatcher.match("saf", in: "Shortcuts and Filters"))
        #expect(prefix.score > scattered.score)
    }

    @Test func acronymLandsOnWordStarts() throws {
        let match = try #require(FuzzyMatcher.match("vsc", in: "Visual Studio Code"))
        #expect(match.positions == [0, 7, 14])
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(FuzzyMatcher.match("SAF", in: "safari") != nil)
    }

    @Test func noSubsequenceMeansNoMatch() {
        #expect(FuzzyMatcher.match("xyz", in: "Safari") == nil)
        #expect(FuzzyMatcher.match("", in: "Safari") == nil)
        #expect(FuzzyMatcher.match("safari browser", in: "Safari") == nil)
    }

    @Test func shorterNameWinsTies() throws {
        let short = try #require(FuzzyMatcher.match("mail", in: "Mail"))
        let long = try #require(FuzzyMatcher.match("mail", in: "Mail Downloader"))
        #expect(short.score > long.score)
    }
}

@MainActor
final class StubProvider: ResultProvider {
    let id: String
    var dismiss: (() -> Void)?
    var onChange: (() -> Void)?
    var replaceQuery: ((String) -> Void)?
    init(id: String = "stub") { self.id = id }
    func results(for query: Query, limit: Int) -> [ScoredItem] { [] }
    func perform(_ action: ItemAction, on item: any SearchItem) {}
}

func entry(_ name: String, in folder: String = "/Applications") -> AppEntry {
    AppEntry(name: name, url: URL(fileURLWithPath: "\(folder)/\(name).app"), bundleIdentifier: nil, icon: nil)
}

@Suite struct RankerTests {
    @Test @MainActor func ordersByScoreThenName() {
        let apps = [entry("System Settings"), entry("Safari"), entry("Sequel Ace"), entry("Xcode")]
        let names = Ranker.rank(apps, query: "s", limit: 8, provider: StubProvider()).map(\.item.title)
        #expect(names.first == "Safari")
        #expect(!names.contains("Xcode"))
    }

    @Test @MainActor func emptyQueryReturnsNothing() {
        #expect(Ranker.rank([entry("Safari")], query: "   ", limit: 8, provider: StubProvider()).isEmpty)
    }

    @Test @MainActor func limitIsRespected() {
        let apps = (1...20).map { entry("App \($0)") }
        #expect(Ranker.rank(apps, query: "app", limit: 5, provider: StubProvider()).count == 5)
    }

}

@Suite struct AliasRankingTests {
    @Test @MainActor func exactAliasBeatsBetterTitleMatch() {
        let apps = [entry("Firefox"), entry("FFmpeg Tool")]
        let results = Ranker.rank(apps, query: "ff", limit: 5, provider: StubProvider(), aliases: { $0.name == "Firefox" ? ["ff"] : [] })
        #expect(results.first?.item.title == "Firefox")
        #expect(results.first?.alias == "ff")
        #expect(results[1].alias == nil)
    }

    @Test @MainActor func exactAliasBeatsExactTitle() {
        let apps = [entry("Notes"), entry("Obsidian")]
        let results = Ranker.rank(apps, query: "notes", limit: 5, provider: StubProvider(), aliases: { $0.name == "Obsidian" ? ["notes"] : [] })
        #expect(results.first?.item.title == "Obsidian")
    }

    @Test @MainActor func shortAliasDoesNotClaimAnOrdinaryPrefixMatch() {
        let results = Ranker.rank([entry("Firefox")], query: "f", limit: 1, provider: StubProvider(), aliases: { _ in ["ff"] })
        #expect(results.first?.alias == nil)
    }

    @Test @MainActor func bundleIdentifierMatchesWithoutAReason() {
        let app = AppEntry(name: "Code", url: URL(fileURLWithPath: "/Applications/Code.app"), bundleIdentifier: "com.microsoft.VSCode", icon: nil)
        let results = Ranker.rank([app], query: "vscode", limit: 1, provider: StubProvider())
        #expect(results.count == 1)
        #expect(results.first?.alias == nil)
    }

    @Test func aliasesDecodeAndDefaultEmpty() throws {
        #expect(Config().aliases.isEmpty)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"aliases": {"ff": "Firefox"}}"#.utf8))
        #expect(config.aliases["ff"] == "Firefox")
    }
}

@Suite struct AliasTableTests {
    @Test func resolvesByNameOrBundleIDCaseInsensitivelyToEveryCopy() {
        let user = entry("Firefox", in: NSHomeDirectory() + "/Applications")
        let system = entry("Firefox")
        let code = AppEntry(name: "Code", url: URL(fileURLWithPath: "/Applications/Code.app"), bundleIdentifier: "com.microsoft.VSCode", icon: nil)
        let table = AliasTable(aliases: ["ff": "FIREFOX", "vs": "com.microsoft.vscode", "x": "Nothing"], apps: [user, system, code])
        #expect(table.aliases(for: user.id) == ["ff"])
        #expect(table.aliases(for: system.id) == ["ff"])
        #expect(table.aliases(for: code.id) == ["vs"])
        #expect(table.unresolved == ["x"])
    }

    @Test func emptyAliasesGiveAnEmptyTable() {
        #expect(AliasTable(aliases: [:], apps: [entry("Safari")]).isEmpty)
    }
}
