import AppKit
import Testing
@testable import MestreCore

private struct FakeItem: SearchItem {
    let id: String
    let title: String
    var keywords: [String] = []
    var kind: ItemKind = .app
    var icon: NSImage? { nil }
    var actions: [ItemAction] { [ItemAction(id: "open", title: "Run")] }
}

@Suite struct QueryTests {
    @Test func splitsFirstWordAndRemainder() {
        let q = Query("  g \t Swift concurrency ")
        #expect(q.text == "g \t Swift concurrency")
        #expect(q.firstWord == "g")
        #expect(q.remainder == "Swift concurrency")
        #expect(q.words == ["g", "swift", "concurrency"])
    }

    @Test func singleWordHasEmptyRemainder() {
        let q = Query("safari")
        #expect(q.remainder == "")
        #expect(!q.isEmpty)
        #expect(Query("   ").isEmpty)
    }
}

@Suite struct GenericRankingTests {
    @Test @MainActor func keywordsMatchWhenTitleDoesNot() {
        let items = [FakeItem(id: "1", title: "Firefox", keywords: ["ff", "browser"]), FakeItem(id: "2", title: "Finder")]
        let results = Ranker.rank(items, query: "ff", limit: 5, provider: StubProvider())
        #expect(results.first?.item.id == "1")
        #expect(results.first?.alias == nil)
    }

    @Test @MainActor func mergeOrdersAcrossProvidersAndNamespacesIds() {
        let (p1, p2) = (StubProvider(id: "one"), StubProvider(id: "two"))
        let a = [ScoredItem(item: FakeItem(id: "x", title: "A"), score: 10, provider: p1)]
        let b = [ScoredItem(item: FakeItem(id: "x", title: "B"), score: 30, provider: p2), ScoredItem(item: FakeItem(id: "c", title: "C"), score: 20, provider: p2)]
        let merged = ResultMerger.merge([a, b], limit: 2)
        #expect(merged.map(\.id) == ["two/x", "two/c"])
    }

    @Test func defaultActionIsFirst() {
        let item = FakeItem(id: "x", title: "X")
        #expect(item.defaultAction?.id == "open")
        #expect(item.action(id: "nope") == nil)
    }
}

@Suite struct SubtitleRoleTests {
    @Test func kindDecidesTheDefaultRole() {
        #expect(FakeItem(id: "a", title: "Safari", kind: .app).subtitleRole == .metadata)
        #expect(FakeItem(id: "f", title: "Notes.md", kind: .file).subtitleRole == .metadata)
        #expect(FakeItem(id: "c", title: "1031", kind: .calculator).subtitleRole == .content)
        #expect(FakeItem(id: "s", title: "sig", kind: .snippet).subtitleRole == .content)
    }

    @Test func everyKindHasARole() {
        for kind in ItemKind.allCases {
            _ = kind.subtitleRole // a new kind must pick a side in the switch
        }
    }
}

@Suite struct AppLocationTests {
    @Test func systemAppsReadAsSystemApplications() {
        let entry = AppEntry(name: "Safari", url: URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"), bundleIdentifier: nil, icon: nil)
        #expect(entry.locationDescription == "/System/Applications")
        let user = AppEntry(name: "X", url: URL(fileURLWithPath: NSHomeDirectory() + "/Applications/X.app"), bundleIdentifier: nil, icon: nil)
        #expect(user.locationDescription == "~/Applications")
    }
}

@Suite struct MergerRankingTests {
    @MainActor private func rows(_ provider: StubProvider, _ pairs: [(String, Double)]) -> [ScoredItem] {
        pairs.map { ScoredItem(item: FakeItem(id: $0.0, title: $0.0), score: $0.1, provider: provider) }
    }

    @Test @MainActor func providerWeightsScaleAndBiasButLeavePinnedRows() {
        let apps = StubProvider(id: "apps"), files = StubProvider(id: "files")
        var ranking = Config.Ranking()
        ranking.providers = ["files": Config.Ranking.Weight(scale: 0.5, bias: 20)]
        let merged = ResultMerger.merge([rows(apps, [("a", 60)]), rows(files, [("f", 60), ("pinned", ScoredItem.pinnedScore)])], limit: 8, ranking: ranking)
        #expect(merged.map(\.item.id) == ["pinned", "a", "f"])
        #expect(merged[2].score == 50)
    }

    @Test @MainActor func aLooseAppMatchBeatsAnExactSettingsPaneByDefault() {
        let apps = StubProvider(id: "apps"), settings = StubProvider(id: "settings")
        let merged = ResultMerger.merge([rows(settings, [("Keyboard", 170)]), rows(apps, [("Blackmagic", 2)])], limit: 8)
        #expect(merged.map(\.item.id) == ["Blackmagic", "Keyboard"])
    }

    @Test func weightParsesAndPrintsItsText() {
        #expect(Config.Ranking.Weight(parsing: "1.2 -5") == Config.Ranking.Weight(scale: 1.2, bias: -5))
        #expect(Config.Ranking.Weight(parsing: "2")?.text == "2" && Config.Ranking.Weight(scale: 1.5, bias: 0.5).text == "1.5 0.5")
        #expect(Config.Ranking.Weight(parsing: "x") == nil && Config.Ranking.Weight(parsing: "1 2 3") == nil)
    }

    @Test func rankingConfigDecodesClampsAndKeepsTheDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"ranking": {"providers": {"files": {"scale": -1}}, "budgetMs": -3}}"#.utf8))
        #expect(config.ranking.weight(for: "files").scale == 0 && config.ranking.weight(for: "apps") == Config.Ranking.Weight())
        #expect(config.ranking.budgetMs == 0 && Config().ranking.budgetMs == 5)
        #expect(config.ranking.weight(for: "settings").bias == -200)
        let neutral = try JSONDecoder().decode(Config.self, from: Data(#"{"ranking": {"providers": {"settings": {"scale": 1}}}}"#.utf8))
        #expect(neutral.ranking.weight(for: "settings") == Config.Ranking.Weight())
    }

    @Test func aChangedDefaultWeightSurvivesASave() throws {
        var config = Config()
        #expect(try ConfigDocs.changes(in: config).isEmpty)
        config.ranking.providers["settings"] = Config.Ranking.Weight()
        let file = ConfigDocs.file(changes: try ConfigDocs.changes(in: config), notes: [:])
        #expect(try JSONDecoder().decode(Config.self, from: Data(file.utf8)) == config)
    }
}

@Suite struct QuickKeyPositionTests {
    @MainActor private func rows(_ pairs: [(String, Double)], alias: String? = nil) -> [ScoredItem] {
        let provider = StubProvider(id: "apps")
        retained.append(provider)
        return pairs.map { ScoredItem(item: FakeItem(id: $0.0, title: $0.0), score: $0.1, provider: provider, alias: alias) }
    }
    @MainActor private var retained: [StubProvider] { get { Self.keep } nonmutating set { Self.keep = newValue } }
    @MainActor private static var keep: [StubProvider] = []

    @Test @MainActor func aKeyGoesFirstOverLooseMatches() {
        #expect(QuickKeys.position(for: "ch", in: rows([("Launch Control", 40), ("Blackmagic", 2)])) == 0)
        #expect(QuickKeys.position(for: "ch", in: []) == 0)
    }

    @Test @MainActor func aKeyYieldsToARowTheTextNames() {
        #expect(QuickKeys.position(for: "sl", in: rows([("Slack", 70), ("Sublime", 20)])) == 1)
        #expect(QuickKeys.position(for: "ff", in: rows([("Firefox", 90), ("Files", 20)], alias: "ff")) == 2)
    }

    @Test @MainActor func aKeyYieldsToComputedAnswersButNotToRowsWeightedDown() {
        #expect(QuickKeys.position(for: "pi", in: rows([("3.14", ScoredItem.pinnedScore), ("Mail", 10)])) == 1)
        #expect(QuickKeys.position(for: "sh", in: rows([("Mail", 10), ("Sharing", -120)])) == 0)
    }
}

@Suite struct FeatureHotkeyTests {
    @Test func featureTargetsParseAndStayOutOfTheWindowList() {
        #expect(HotkeyTable.featureID(in: "feature:clipboard") == "clipboard")
        #expect(HotkeyTable.featureID(in: "Clipboard") == nil && HotkeyTable.windowLayout(in: "feature:clipboard") == nil)
        let table = HotkeyTable(hotkeys: ["hyper+v": "feature:clipboard"], panelHotKey: .default, keyCodes: ["v": 9])
        #expect(table.entries.map(\.target) == ["feature:clipboard"] && table.windowEntries.isEmpty)
        #expect(table.unresolvedTargets(in: []) { HotkeyTable.featureID(in: $0) == "clipboard" }.isEmpty)
        #expect(table.unresolvedTargets(in: []) == ["feature:clipboard"])
    }
}

@Suite struct ProviderTitleTests {
    @Test @MainActor func titleSpellsOutTheID() {
        #expect(StubProvider(id: "openWindows").title == "Open Windows")
        #expect(StubProvider(id: "apps").title == "Apps" && StubProvider(id: "keepAwake").title == "Keep Awake")
    }
}
