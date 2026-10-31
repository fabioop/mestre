import Foundation
import Testing
@testable import MestreCore

@Suite struct SettingsCatalogTests {
    @Test func idsAreUnique() {
        let ids = SettingsCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func findsASettingByNameOrByWhatItDoes() {
        #expect(SettingsCatalog.search("dark").first?.id == "appearance")
        #expect(SettingsCatalog.search("password").first?.id == "clipboard.exclude")
        #expect(SettingsCatalog.search("WIDTH").first?.id == "width")
        #expect(SettingsCatalog.search("clipboard items").first?.id == "clipboard.items")
        #expect(SettingsCatalog.search("kagi").first?.page == .features)
        #expect(SettingsCatalog.search("kagi").first?.feature == .web)
    }

    @Test func aTitleMatchBeatsAKeyword() {
        let ids = SettingsCatalog.search("theme").map(\.id)
        #expect(ids.first == "theme")
    }

    @Test func nothingToSearchForFindsNothing() {
        #expect(SettingsCatalog.search("   ").isEmpty)
        #expect(SettingsCatalog.search("zzzz").isEmpty)
    }

    @Test func everyFeatureHasASwitchThatChangesTheConfig() {
        for feature in SettingsFeature.allCases {
            var config = Config()
            let before = config[keyPath: feature.isEnabled]
            config[keyPath: feature.isEnabled] = !before
            #expect(config != Config(), "\(feature)")
        }
    }

    @Test func orderedChoicesToggleMoveAndRespectTheLimit() {
        #expect(OrderedChoice.toggled("b", in: ["a", "b"]) == ["a"])
        #expect(OrderedChoice.toggled("c", in: ["a"]) == ["a", "c"])
        #expect(OrderedChoice.toggled("c", in: ["a", "b"], limit: 2) == ["a", "b"])
        #expect(OrderedChoice.moved("b", by: -1, in: ["a", "b"]) == ["b", "a"])
        #expect(OrderedChoice.moved("a", by: -1, in: ["a", "b"]) == ["a", "b"])
        #expect(OrderedChoice.moved("z", by: 1, in: ["a", "b"]) == ["a", "b"])
    }

    @Test func removingADefaultHotkeyDisablesIt() {
        let defaults = ["ctrl+option+left": "window:leftHalf"]
        #expect(HotkeyEdits.removing("ctrl+option+left", from: [:], defaults: defaults) == ["ctrl+option+left": ""])
        #expect(HotkeyEdits.removing("cmd+t", from: ["cmd+t": "Terminal"], defaults: defaults).isEmpty)
    }

    @Test func movingAHotkeyLeavesNoTwoKeysForOneTarget() {
        let defaults = ["ctrl+option+left": "window:leftHalf"]
        let moved = HotkeyEdits.binding("window:leftHalf", to: "cmd+option+left", replacing: "ctrl+option+left", in: [:], defaults: defaults)
        #expect(moved == ["ctrl+option+left": "", "cmd+option+left": "window:leftHalf"])
        let table = HotkeyTable(hotkeys: moved, defaults: defaults, panelHotKey: .default, keyCodes: [:])
        #expect(table.windowEntries.map(\.text) == ["cmd+option+left"])
        let user = HotkeyEdits.binding("Terminal", to: "cmd+y", replacing: "cmd+t", in: ["cmd+t": "Terminal"], defaults: defaults)
        #expect(user == ["cmd+y": "Terminal"])
    }

    private var customised: Config {
        var config = Config()
        config.panel.theme = "ulm"
        config.panel.width = 900
        config.hotkeys = ["cmd+t": "Terminal"]
        config.clipboard.keyword = "cb"
        config.search.maxResults = 20
        config.search.scanDepth = 5
        config.hotKey = KeyCombo(keyCode: 49, modifiers: .command, keyLabel: "Space")
        config.quicklinks = [Quicklink(name: "Maps", url: "https://maps.example")]
        config.snippets.items = [Snippet(name: "Sig", text: "Regards")]
        config.snippets.dateFormat = "dd/MM/yyyy"
        config.scripts.items = [ScriptFilter(name: "S", keyword: "s", command: "x")]
        config.aliases = ["ff": "Firefox"]
        config.onboarding.showWelcome = false
        config.startup.launchAtLogin = true
        return config
    }

    @Test func resettingAllKeepsWhatYouWroteAndNothingElse() {
        let reset = customised.resettingAll()
        var expected = Config()
        expected.quicklinks = customised.quicklinks
        expected.snippets.items = customised.snippets.items
        expected.scripts.items = customised.scripts.items
        expected.aliases = customised.aliases
        expected.onboarding.showWelcome = false
        expected.startup.launchAtLogin = true
        #expect(reset == expected)
    }

    @Test func resettingAPageLeavesTheOthersAlone() {
        let look = customised.resetting(.appearance)
        #expect(look.panel == Config().panel && look.search.maxResults == 8)
        #expect(look.hotkeys == customised.hotkeys && look.clipboard.keyword == "cb" && look.search.scanDepth == 5)

        let features = customised.resetting(.features)
        #expect(features.clipboard == Config().clipboard && features.snippets.dateFormat == Config().snippets.dateFormat)
        #expect(features.snippets.items == customised.snippets.items && features.panel.theme == "ulm")

        let shortcuts = customised.resetting(.shortcuts)
        #expect(shortcuts.hotkeys.isEmpty && shortcuts.hotKey == customised.hotKey)

        let general = customised.resetting(.general)
        #expect(general.hotKey == .default && general.hotkeys == customised.hotkeys)

        #expect(customised.resetting(.library) == customised)
    }

    @Test func launchAtLoginTravelsWithTheFileAndStaysOutUntilChosen() throws {
        #expect(Config().startup.launchAtLogin == nil)
        var config = Config()
        config.startup.launchAtLogin = true
        let round = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(round.startup.launchAtLogin == true)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).startup.launchAtLogin == nil)
    }
}

@Suite struct StatusMarkTests {
    @Test func oneDotPerFeatureUpToWhatFits() {
        #expect(StatusMark(activeCount: 0).dots == 0)
        #expect(StatusMark(activeCount: 2).dots == 2)
        #expect(StatusMark(activeCount: 9).dots == 3)
        #expect(StatusMark(activeCount: -1).dots == 0)
    }

    @Test func everyStateIsATemplateOfTheSameSize() {
        let images = (0...3).map { StatusMark(activeCount: $0).image }
        let allTemplates = images.allSatisfy(\.isTemplate)
        let widths = Set(images.map(\.size.width))
        #expect(allTemplates)
        #expect(widths.count == 1)
    }
}
