import Foundation
import Testing
@testable import MestreCore

/// A menu tree standing in for the Accessibility elements: an item is a node, a menu is the
/// list of its items.
private final class FakeMenu {
    let title: String
    var enabled = true
    var shortcut: String?
    var children: [FakeMenu]?

    init(_ title: String, enabled: Bool = true, shortcut: String? = nil, _ children: [FakeMenu]? = nil) {
        self.title = title
        self.enabled = enabled
        self.shortcut = shortcut
        self.children = children
    }
}

private func walk(_ bar: [FakeMenu], maxDepth: Int = 4, maxItems: Int = 1000, shouldStop: @escaping () -> Bool = { false }) -> [MenuEntry<FakeMenu>] {
    // The submenu element is the item itself; `items` then lists its children.
    MenuWalker.walk(
        bar: bar, maxDepth: maxDepth, maxItems: maxItems,
        read: { MenuNode(title: $0.title, isEnabled: $0.enabled, shortcut: $0.shortcut, submenu: $0.children == nil ? nil : $0) },
        items: { $0.children ?? [] },
        shouldStop: shouldStop
    )
}

private let sampleBar = [
    FakeMenu("Apple", [FakeMenu("About This Mac"), FakeMenu("System Settings…")]),
    FakeMenu("Preview", [FakeMenu("Settings…", shortcut: "⌘,"), FakeMenu(""), FakeMenu("Quit Preview", shortcut: "⌘Q")]),
    FakeMenu("File", [
        FakeMenu("Open…", shortcut: "⌘O"),
        FakeMenu("Export", [FakeMenu("PDF"), FakeMenu("PNG", [FakeMenu("Small"), FakeMenu("Large")])]),
        FakeMenu("Print", [FakeMenu("PDF")]),
        FakeMenu("Revert", enabled: false),
        FakeMenu("Recent", enabled: false, [FakeMenu("a.pdf")]),
    ]),
]

@Suite struct MenuWalkerTests {
    @Test func listsLeavesInMenuOrderWithTheirPaths() {
        let entries = walk(sampleBar)
        #expect(entries.map(\.title) == ["Settings…", "Quit Preview", "Open…", "PDF", "Small", "Large", "PDF"])
        #expect(entries[3].path == ["File", "Export"])
        #expect(entries[3].subtitle == "File › Export")
        #expect(entries[0].subtitle == "Preview · ⌘,")
    }

    @Test func skipsTheAppleMenuSeparatorsAndDisabledItems() {
        let titles = walk(sampleBar).map(\.title)
        #expect(!titles.contains("About This Mac"))
        #expect(!titles.contains(""))
        #expect(!titles.contains("Revert"))
        #expect(!titles.contains("a.pdf"))  // under a disabled submenu
    }

    @Test func depthCountsTheMenuBarsOwnMenus() {
        #expect(walk(sampleBar, maxDepth: 1).map(\.title) == ["Settings…", "Quit Preview", "Open…"])
        #expect(walk(sampleBar, maxDepth: 2).map(\.title) == ["Settings…", "Quit Preview", "Open…", "PDF", "PDF"])
    }

    @Test func stopsAtTheItemLimitAndTheDeadline() {
        #expect(walk(sampleBar, maxItems: 2).count == 2)
        var asked = 0
        let entries = walk(sampleBar, shouldStop: { asked += 1; return asked > 3 })
        #expect(entries.map(\.title) == ["Settings…", "Quit Preview"])  // asked per item, separators too
    }

    @Test func sameNameInOneMenuGetsDistinctIds() {
        let bar = [FakeMenu("Apple", []), FakeMenu("Window", [FakeMenu("Notes"), FakeMenu("Notes")])]
        let ids = walk(bar).map(\.id)
        #expect(ids == ["Window›Notes", "Window›Notes#1"])
        #expect(Set(walk(sampleBar).map(\.id)).count == 7)  // PDF under Export and under Print
    }
}

@Suite struct MenuShortcutTests {
    @Test func charactersAndModifiers() {
        #expect(MenuShortcut.format(character: "e", modifiers: 1, glyph: nil, virtualKey: nil) == "⇧⌘E")
        #expect(MenuShortcut.format(character: "S", modifiers: 0, glyph: nil, virtualKey: nil) == "⌘S")
        #expect(MenuShortcut.format(character: "S", modifiers: nil, glyph: nil, virtualKey: nil) == "⌘S")
        #expect(MenuShortcut.format(character: "f", modifiers: 4, glyph: nil, virtualKey: nil) == "⌃⌘F")
        #expect(MenuShortcut.format(character: "t", modifiers: 2 | 1, glyph: nil, virtualKey: nil) == "⌥⇧⌘T")
        #expect(MenuShortcut.format(character: ",", modifiers: 0, glyph: nil, virtualKey: nil) == "⌘,")
    }

    @Test func noCommandMeansNoCommandKey() {
        #expect(MenuShortcut.format(character: "a", modifiers: 8, glyph: nil, virtualKey: nil) == "A")
        #expect(MenuShortcut.format(character: nil, modifiers: 8 | 4, glyph: 0x6F + 1, virtualKey: nil) == "⌃F2")
    }

    @Test func glyphsAndFunctionKeys() {
        #expect(MenuShortcut.format(character: nil, modifiers: 0, glyph: 0x17, virtualKey: nil) == "⌘⌫")
        #expect(MenuShortcut.format(character: nil, modifiers: 0, glyph: 0x0B, virtualKey: nil) == "⌘↩")
        #expect(MenuShortcut.format(character: nil, modifiers: 2, glyph: 0x64, virtualKey: nil) == "⌥⌘←")
        #expect(MenuShortcut.format(character: nil, modifiers: 8, glyph: 0x6F, virtualKey: nil) == "F1")
        #expect(MenuShortcut.format(character: "\u{F704}", modifiers: 8, glyph: nil, virtualKey: nil) == "F1")
        #expect(MenuShortcut.format(character: "\u{F702}", modifiers: 0, glyph: nil, virtualKey: nil) == "⌘←")
        #expect(MenuShortcut.format(character: "\u{1B}", modifiers: 8, glyph: nil, virtualKey: nil) == "⎋")
        #expect(MenuShortcut.format(character: nil, modifiers: 0, glyph: nil, virtualKey: 0x7A) == "⌘F1")
    }

    @Test func noKeyMeansNoShortcut() {
        #expect(MenuShortcut.format(character: nil, modifiers: 0, glyph: nil, virtualKey: nil) == nil)
        #expect(MenuShortcut.format(character: "", modifiers: 0, glyph: 0, virtualKey: 0) == nil)
        #expect(MenuShortcut.format(character: nil, modifiers: 0, glyph: 0x5A, virtualKey: nil) == nil)
    }
}

@Suite struct MenuSearchResultTests {
    @Test @MainActor func noTextListsEverythingInMenuOrder() {
        let entries = walk(sampleBar)
        let rows = MenuSearch.results(entries, matching: "", limit: 3, provider: StubProvider())
        #expect(rows.map(\.item.title) == ["Settings…", "Quit Preview", "Open…"])
    }

    @Test @MainActor func matchesTitleAndPath() {
        let entries = walk(sampleBar)
        let rows = MenuSearch.results(entries, matching: "quit", limit: 8, provider: StubProvider())
        #expect(rows.first?.item.title == "Quit Preview")
        let exported = MenuSearch.results(entries, matching: "export pdf", limit: 8, provider: StubProvider())
        #expect(exported.first?.item.subtitle == "File › Export")
        let large = MenuSearch.results(entries, matching: "png large", limit: 8, provider: StubProvider())
        #expect(large.first?.item.title == "Large")
    }

    @Test func preparedMatchingScoresLikePlainMatching() {
        for (query, candidate) in [("exp", "Export as PDF…"), ("sas", "Save As"), ("zz", "Zoom"), ("ŞA", "Şarkı Ara"), ("x", "")] {
            #expect(FuzzyMatcher.match(Array(query.lowercased()), in: FuzzyMatcher.Prepared(candidate)) == FuzzyMatcher.match(query, in: candidate))
        }
    }

    @Test @MainActor func threeThousandItemsRankWithinBudget() {
        let menus = (0..<30).map { m in
            FakeMenu("Menu \(m)", (0..<20).map { i in
                FakeMenu("Group \(i)", (0..<5).map { FakeMenu("Command Number \(m * 100 + i * 5 + $0) Action") })
            })
        }
        let start = ContinuousClock.now
        let entries = walk([FakeMenu("Apple", [])] + menus, maxItems: 3000)
        print("walking 3 000 fake menu items: \(ContinuousClock.now - start)")
        #expect(entries.count == 3000)
        let provider = StubProvider()
        let queries = ["c", "co", "com", "group 3", "menu 12 action", "zzz"]
        _ = MenuSearch.results(entries, matching: "warm", limit: 8, provider: provider)
        let rankStart = ContinuousClock.now
        for query in queries { _ = MenuSearch.results(entries, matching: query, limit: 8, provider: provider) }
        let perQuery = (ContinuousClock.now - rankStart) / queries.count
        print("ranking 3 000 menu items: \(perQuery) per query")
        // A release build ranks these in about 2 ms; debug builds are 20–30 times slower here,
        // so this only catches a return to unprepared matching (about 70 ms in release).
        let ceiling: Duration = ProcessInfo.processInfo.environment["CI"] == nil ? .milliseconds(250) : .milliseconds(1000)
        #expect(perQuery < ceiling, "ranking took \(perQuery) per query (debug build)")
    }
}

@Suite struct MenusConfigTests {
    @Test func defaultsAndClamps() throws {
        let defaults = try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).menus
        #expect(defaults == Config.Menus())
        #expect(defaults.enabled && defaults.keyword == "menu" && !defaults.searchEverywhere && !defaults.readOnOpen)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"menus": {"keyword": "Menus please", "maxDepth": 40, "maxItems": 0, "readTimeoutSeconds": 0, "cacheSeconds": -1}}"#.utf8))
        #expect(config.menus.keyword == "menus")
        #expect(config.menus.maxDepth == 10 && config.menus.maxItems == 1)
        #expect(config.menus.readTimeoutSeconds == 0.1 && config.menus.cacheSeconds == 0)
    }

    @Test func kindLabel() {
        #expect(ItemKind.menuItem.label == "Menu")
        #expect(ItemKind.menuItem.subtitleRole == .content)
    }
}
