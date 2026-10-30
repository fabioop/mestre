import Carbon.HIToolbox
import Foundation
import Testing
@testable import MestreCore

@Suite struct KeyComboParsingTests {
    @Test func parsesNamedKeysAndModifiers() throws {
        let combo = try #require(KeyCombo(parsing: "option+space"))
        #expect(combo.keyCode == UInt32(kVK_Space))
        #expect(combo.modifiers == .option)
        #expect(combo.displayString == "⌥Space")
    }

    @Test func acceptsAliasesAndSpacing() throws {
        let combo = try #require(KeyCombo(parsing: " Cmd + Shift + F5 "))
        #expect(combo.modifiers == [.command, .shift])
        #expect(combo.keyCode == UInt32(kVK_F5))
    }

    @Test func resolvesLettersThroughTheLayout() throws {
        let combo = try #require(KeyCombo(parsing: "ctrl+k", keyCodes: ["k": 40]))
        #expect(combo.keyCode == 40)
        #expect(combo.keyLabel == "K")
    }

    @Test func rejectsGarbage() {
        #expect(KeyCombo(parsing: "option+") == nil)
        #expect(KeyCombo(parsing: "option+space+k") == nil)
        #expect(KeyCombo(parsing: "nosuchkey", keyCodes: [:]) == nil)
    }

    @Test func configStringRoundTrips() throws {
        let original = try #require(KeyCombo(parsing: "ctrl+option+cmd+return"))
        #expect(original.configString == "ctrl+option+cmd+return")
        #expect(KeyCombo(parsing: original.configString) == original)
        let hyper = try #require(KeyCombo(parsing: "ctrl+option+shift+cmd+return"))
        #expect(hyper.configString == "hyper+return")
        #expect(KeyCombo(parsing: hyper.configString) == hyper)
    }
}

@Suite struct ConfigTests {
    private func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    @Test func emptyObjectGivesDefaults() throws {
        let config = try decode("{}")
        #expect(config == Config())
        #expect(config.hotKey == .default)
        #expect(config.search.includeSystemApps == false)
    }

    @Test func partialSearchSectionKeepsOtherDefaults() throws {
        let config = try decode(#"{"search": {"includeSystemApps": true}}"#)
        #expect(config.search.includeSystemApps)
        #expect(config.search.appDirectories == ["/Applications", "~/Applications"])
        #expect(config.search.maxResults == 8)
    }

    @Test func systemFoldersAppendedOnlyWhenEnabled() {
        var config = Config()
        #expect(config.resolvedAppDirectories.map(\.path) == ["/Applications", NSHomeDirectory() + "/Applications"])
        config.search.includeSystemApps = true
        #expect(config.resolvedAppDirectories.map(\.path).contains("/System/Applications"))
    }

    @Test func badHotKeyIsAnError() {
        #expect(throws: DecodingError.self) { try decode(#"{"hotKey": "wat+ever+more"}"#) }
    }

    @Test func encodesHotKeyAsText() throws {
        let data = try JSONEncoder().encode(Config())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hotKey"] as? String == "option+space")
    }
}

@Suite struct PanelConfigTests {
    @Test func themeKeysDecodeAndParse() throws {
        #expect(Config().panel.appearance == .system)
        #expect(Config().panel.accentChoice == .mestre)
        #expect(Config().panel.accent == nil)
        var system = Config(); system.panel.accentColor = "System"
        #expect(system.panel.accentChoice == .system)
        let config = try JSONDecoder().decode(Config.self, from: Data("{\"panel\": {\"appearance\": \"dark\", \"accentColor\": \"#ff8800\"}}".utf8))
        #expect(config.panel.appearance == .dark)
        #expect(config.panel.accent?.hex == "#FF8800")
        var bad = Config(); bad.panel.accentColor = "nope"
        #expect(bad.panel.accent == nil && bad.panel.accentChoice == nil)
        let lenient = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"appearance": "Dark ", "material": "auto"}}"#.utf8))
        #expect(lenient.panel.appearance == .dark)
        #expect(lenient.panel.material == .glass)
    }

    @Test func panelSectionDecodesPartially() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"width": 800, "material": "hud"}}"#.utf8))
        #expect(config.panel.width == 800)
        #expect(config.panel.material == .hud)
        #expect(config.panel.rowHeight == 42)
        #expect(config.panel.iconSize == 28 && config.panel.showFooter)
    }

    @Test func panelValuesAreClamped() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"width": 10, "rowHeight": -5, "maxVisibleRows": 0, "verticalPosition": 3}}"#.utf8))
        #expect(config.panel.width == 200)
        #expect(config.panel.rowHeight == 20)
        #expect(config.panel.maxVisibleRows == 1)
        #expect(config.panel.verticalPosition == 0.9)
        let icon = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"rowHeight": 30, "iconSize": 64}}"#.utf8))
        #expect(icon.panel.iconSize == 30) // never taller than the row
    }

    @Test func subtitlesKeyDecodesWithFallback() throws {
        #expect(Config().panel.subtitles == .selected)
        let always = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"subtitles": "always"}}"#.utf8))
        #expect(always.panel.subtitles == .always)
        let bogus = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"subtitles": "sometimes"}}"#.utf8))
        #expect(bogus.panel.subtitles == .selected)
    }

    @Test func toastCompactAndCompletionKeysDecodeAndClamp() throws {
        #expect(Config().panel.toastSeconds == 1.5 && Config().panel.compact == false && Config().panel.completion == .scope)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"toastSeconds": -2, "compact": true, "completion": "text"}}"#.utf8))
        #expect(config.panel.toastSeconds == 0 && config.panel.compact && config.panel.completion == .text)
    }

    @Test func unknownMaterialFallsBackToDefault() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"panel": {"material": "frosted"}}"#.utf8))
        #expect(config.panel.material == .glass)
    }

    @Test func panelSectionRoundTrips() throws {
        var config = Config()
        config.panel.cornerRadius = 0
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }
}

@Suite struct HomeConfigTests {
    @Test func defaultsAndDecoding() throws {
        #expect(Config().home.sections == [.recent, .features, .commands])
        #expect(Config().panel.material == .glass)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"home": {"sections": ["Features", "features", "bogus", "recent"], "recentCount": -3, "hidden": ["dictionary"]}}"#.utf8))
        #expect(config.home.sections == [.features, .recent] && config.home.recentCount == 0 && config.home.hidden == ["dictionary"])
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data).home.sections == [.features, .recent])
    }
}

@Suite struct KeepAwakeConfigTests {
    @Test func decodesWithClampsAndDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"keepAwake": {"keyword": "Caffeine please", "durationsMinutes": [0, 10, -5], "endWhenBatteryBelow": 150}}"#.utf8))
        #expect(config.keepAwake.keyword == "caffeine")
        #expect(config.keepAwake.durationsMinutes == [10])
        #expect(config.keepAwake.endWhenBatteryBelow == 100)
        #expect(config.keepAwake.enabled && !config.keepAwake.allowDisplaySleep && config.keepAwake.menuBarIcon)
    }
}

@Suite struct OnboardingConfigTests {
    @Test func welcomeDefaultsOnAndRoundTrips() throws {
        #expect(Config().onboarding.showWelcome)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"onboarding": {"showWelcome": false}}"#.utf8))
        #expect(config.onboarding.showWelcome == false)
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data).onboarding.showWelcome == false)
    }
}

@Suite struct DebugConfigTests {
    @Test func debugSectionDefaultsOffAndDecodes() throws {
        #expect(Config().debug.logTimings == false)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"debug": {"logTimings": true}}"#.utf8))
        #expect(config.debug.logTimings)
    }
}

@Suite struct HyperAndHotkeysTests {
    @Test func hyperExpandsToAllFourModifiers() throws {
        let combo = try #require(KeyCombo(parsing: "hyper+t", keyCodes: ["t": 17]))
        #expect(combo.modifiers == [.command, .option, .control, .shift])
        #expect(combo.displayString == "Hyper+T")
        #expect(combo.configString == "hyper+t")
    }

    @Test func hotkeysDecodeAndDefaultEmpty() throws {
        #expect(Config().hotkeys.isEmpty)
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"hotkeys": {"hyper+t": "Terminal"}}"#.utf8))
        #expect(config.hotkeys["hyper+t"] == "Terminal")
    }
}

@Suite struct HotkeyTableTests {
    let codes: [Character: UInt16] = ["t": 17, "f": 3]

    @Test func parsesSortsAndRejectsDuplicates() {
        let table = HotkeyTable(
            hotkeys: ["hyper+t": "Terminal", "cmd+shift+f": "Firefox", "shift+cmd+f": "Finder", "option+space": "Safari", "nope": "X"],
            panelHotKey: .default, keyCodes: codes
        )
        #expect(table.entries.map(\.text) == ["cmd+shift+f", "hyper+t"])
        #expect(table.duplicates == ["option+space", "shift+cmd+f"])
        #expect(table.invalid == ["nope"])
    }

    @Test func reportsTargetsNoAppMatches() {
        let table = HotkeyTable(hotkeys: ["hyper+t": "terminal", "hyper+f": "com.nope.App"], panelHotKey: .default, keyCodes: codes)
        let apps = [AppEntry(name: "Terminal", url: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), bundleIdentifier: "com.apple.Terminal", icon: nil)]
        #expect(table.unresolvedTargets(in: apps) == ["com.nope.App"])
    }
}

@Suite struct CommandsConfigTests {
    @Test func commandsSectionDecodesPartially() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"commands": {"hidden": ["shutDown"]}}"#.utf8))
        #expect(config.commands.hidden == ["shutDown"])
        #expect(config.commands.enabled && config.commands.confirmDestructive)
    }
}

@Suite struct HotkeyTargetResolutionTests {
    @Test func commandsCountAsResolved() {
        let table = HotkeyTable(hotkeys: ["hyper+l": "lockScreen", "hyper+z": "nothing"], panelHotKey: .default, keyCodes: ["l": 37, "z": 6])
        let unresolved = table.unresolvedTargets(in: []) { $0 == "lockScreen" }
        #expect(unresolved == ["nothing"])
    }
}

@Suite struct ShortcutsTests {
    @Test func parsesNamesTrimmedAndDeduplicated() {
        let names = ShortcutsList.parse("Generate QR Code\n  Search in Passwords \n\nGenerate QR Code\n")
        #expect(names == ["Generate QR Code", "Search in Passwords"])
        #expect(ShortcutsList.parse("").isEmpty)
    }

    @Test func shortcutsConfigDecodes() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"shortcuts": {"refreshIntervalSeconds": -5}}"#.utf8))
        #expect(config.shortcuts.refreshIntervalSeconds == 0)
        #expect(config.shortcuts.enabled)
    }
}

@Suite struct QuickKeysConfigTests {
    @Test func quickKeysSurviveASaveAndBadKeysDrop() throws {
        var config = Config()
        config.quickKeys.keys = ["sl": "sleep"]
        config.quickKeys.enabled = false
        let saved = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(saved.quickKeys == config.quickKeys)
        let decoded = try JSONDecoder().decode(Config.self, from: Data(#"{"quickKeys": {"keys": {" SL ": "sleep", "toolong": "x"}}}"#.utf8))
        #expect(decoded.quickKeys.keys == ["sl": "sleep"])
    }
}

@Suite struct ConfigDocsTests {
    @Test func everyEncodedSectionHasADocAndTheDumpStaysValidJSON() throws {
        let dump = try ConfigDocs.dump(Config(), docs: true)
        let object = try JSONSerialization.jsonObject(with: Data(dump.utf8)) as? [String: Any]
        #expect(object?["_doc.panel"] as? String == ConfigDocs.doc(for: .panel))
        #expect(try JSONDecoder().decode(Config.self, from: Data(dump.utf8)) == Config())
        #expect(dump.range(of: "\"hotKey\"")!.lowerBound < dump.range(of: "\"panel\"")!.lowerBound)  // file order, not alphabetical
        let starter = try JSONSerialization.jsonObject(with: Data(ConfigDocs.starterFile().utf8)) as? [String: Any]
        #expect(starter?["_"] != nil)
        #expect((try? JSONDecoder().decode(Config.self, from: Data(ConfigDocs.starterFile().utf8))) == Config())
    }
}

@Suite struct ConfigSaveTests {
    @Test func onlyChangedLeavesAreWrittenAndNotesStayFirst() throws {
        var config = Config()
        config.panel.width = 760
        config.aliases = ["ff": "Firefox"]
        let changes = try ConfigDocs.changes(in: config)
        #expect(Set(changes.keys) == ["panel", "aliases"])
        #expect((changes["panel"] as? [String: Any])?.keys.sorted() == ["width"])
        #expect(try ConfigDocs.changes(in: Config()).isEmpty)
        let file = ConfigDocs.file(changes: changes, notes: ["_": "note", "ignored": 1])
        #expect(file.contains("\"_\": \"note\""))
        let decoded = try JSONDecoder().decode(Config.self, from: Data(file.utf8))
        #expect(decoded == config && !file.contains("ignored"))
        #expect(file.range(of: "\"_\"")!.lowerBound < file.range(of: "\"panel\"")!.lowerBound)
    }
}
