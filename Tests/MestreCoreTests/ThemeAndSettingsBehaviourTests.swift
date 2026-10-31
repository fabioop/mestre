import AppKit
import Carbon.HIToolbox
import Foundation
@testable import MestreCore
import Testing

@Suite struct ThemeNameAndColourTests {
    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theDefaultThemeHasNoFileToLookUp() throws {
        #expect(ThemeLibrary.fileURL(for: ThemeLibrary.defaultName, userDirectory: try tempFolder()) == nil)
    }

    @Test func aUserFileCanReplaceTheDefault() throws {
        let folder = try tempFolder()
        try Data(#"{"cornerRadius": 7}"#.utf8).write(to: folder.appendingPathComponent("mestre.json"))
        #expect(ThemeLibrary.load("mestre", userDirectory: folder).theme.cornerRadius == 7)
    }

    @Test func theConfigKeepsOneSpellingOfATheme() throws {
        func panel(_ json: String) throws -> Config.Panel { try JSONDecoder().decode(Config.Panel.self, from: Data(json.utf8)) }
        #expect(try panel(#"{"theme": "ULM "}"#).theme == "ulm")
        #expect(try panel(#"{"theme": ""}"#).theme == ThemeLibrary.defaultName)
    }

    @Test func aCopyUsesTheThemeHoweverItIsSpelledAndRefusesAnythingElse() throws {
        let folder = try tempFolder()
        try Data(#"{"cornerRadius": 7}"#.utf8).write(to: folder.appendingPathComponent("mine.json"))
        let copy = try ThemeLibrary.makeCopy(of: "MINE ", userDirectory: folder)
        #expect(copy == "mine-custom")
        #expect(ThemeLibrary.load(copy, userDirectory: folder).theme.cornerRadius == 7)
        #expect(throws: (any Error).self) { try ThemeLibrary.makeCopy(of: "../../x", userDirectory: folder) }
        #expect(throws: (any Error).self) { try ThemeLibrary.makeCopy(of: "missing", userDirectory: folder) }
        #expect(!FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("x-custom.json").path))
    }

    @Test func aColourThatDoesntParseDecidesNothing() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(##"{"colors": {"panel": "#e9e8e", "accent": "blurple"}}"##.utf8))
        var panel = Config.Panel()
        panel.material = .hud
        panel.accentColor = "#ff8800"
        let applied = theme.applied(to: panel, dark: false)
        #expect(applied.material == .hud && applied.accentColor == "#ff8800")
    }

    @Test func aThemeDecidesOnlyWhatItSets() throws {
        let empty = try JSONDecoder().decode(Theme.self, from: Data(#"{"light": {}, "dark": {}}"#.utf8))
        #expect(empty.overrides(dark: false) == Theme.Overrides(accent: false, material: false, cornerRadius: false, fieldHeight: false, queryFontSize: false))
        let painted = try JSONDecoder().decode(Theme.self, from: Data(##"{"cornerRadius": 3, "light": {"panel": "#ffffff", "accent": "#000000"}}"##.utf8))
        #expect(painted.overrides(dark: false) == Theme.Overrides(accent: true, material: true, cornerRadius: true, fieldHeight: false, queryFontSize: false))
    }

    @Test func clearGlassCanBeChosen() throws {
        let panel = try JSONDecoder().decode(Config.Panel.self, from: Data(#"{"material": "clearGlass"}"#.utf8))
        #expect(panel.material == .clearGlass)
        let lower = try JSONDecoder().decode(Config.Panel.self, from: Data(#"{"material": "CLEARGLASS"}"#.utf8))
        #expect(lower.material == .clearGlass)
        let theme = try JSONDecoder().decode(Theme.self, from: Data(#"{"material": "clearGlass"}"#.utf8))
        #expect(theme.material == .clearGlass)
    }
}

@Suite struct RecordedShortcutTests {
    private let keys: [Character: UInt16] = ["1": 18, "+": 24, "k": 40]

    @Test func aShiftedDigitIsStoredByItsOwnKey() throws {
        let combo = try #require(KeyCombo.recorded(keyCode: 18, modifiers: [.command, .shift], characters: "1", keyCodes: keys))
        #expect(combo.configString == "shift+cmd+1")
        #expect(KeyCombo(parsing: combo.configString, keyCodes: keys)?.keyCode == 18)
    }

    @Test func thePlusKeyRoundTrips() throws {
        let combo = try #require(KeyCombo.recorded(keyCode: 24, modifiers: [.control, .option], characters: "+", keyCodes: keys))
        #expect(combo.configString == "ctrl+option++")
        #expect(KeyCombo(parsing: "ctrl+option++", keyCodes: keys)?.keyCode == 24)
    }

    @Test func aDeadKeyIsStoredByItsCode() throws {
        let combo = try #require(KeyCombo.recorded(keyCode: 30, modifiers: [.command], characters: "", keyCodes: keys))
        #expect(combo.configString == "cmd+key30")
        #expect(KeyCombo(parsing: "cmd+key30", keyCodes: keys)?.keyCode == 30)
    }

    @Test func aKeyTheFileCantReadBackIsRefused() {
        #expect(KeyCombo.recorded(keyCode: 18, modifiers: [.command], characters: "!", keyCodes: keys) == nil)
    }

    @Test func spotlightKeepsItsShortcutUntilTurnedOff() {
        #expect(KeyCombo.spotlightHasShortcut(symbolicHotKeys: nil))
        #expect(KeyCombo.spotlightHasShortcut(symbolicHotKeys: ["64": ["enabled": true]]))
        #expect(!KeyCombo.spotlightHasShortcut(symbolicHotKeys: ["64": ["enabled": false]]))
        #expect(KeyCombo(parsing: KeyCombo.spotlight.configString)?.isSameKey(as: .spotlight) == true)
    }

    @Test func switchingSpotlightKeepsItsKeyAndEverythingElse() throws {
        let existing: [String: Any] = ["64": ["enabled": true, "value": ["type": "custom"]], "65": ["enabled": true]]
        let off = KeyCombo.spotlightHotKeys(existing, enabled: false)
        #expect(!KeyCombo.spotlightHasShortcut(symbolicHotKeys: off))
        #expect(((off["64"] as? [String: Any])?["value"] as? [String: String])?["type"] == "custom")
        #expect(off["65"] != nil)
        #expect(KeyCombo.spotlightHasShortcut(symbolicHotKeys: KeyCombo.spotlightHotKeys(off, enabled: true)))
        let fresh = try #require(KeyCombo.spotlightHotKeys(nil, enabled: false)["64"] as? [String: Any])
        #expect((fresh["value"] as? [String: Any])?["parameters"] as? [Int] == [32, 49, 1_048_576])
    }

    @Test func onlyKeysThatDontTypeCanBeBare() {
        #expect(KeyCombo.typesText(keyCode: 40) && KeyCombo.typesText(keyCode: Int(kVK_Space)))
        #expect(!KeyCombo.typesText(keyCode: Int(kVK_UpArrow)) && !KeyCombo.typesText(keyCode: Int(kVK_Tab)))
    }
}

@Suite struct HotkeyEditTests {
    private let defaults = ["ctrl+option+left": "window:leftHalf"]

    @Test func aDefaultIsFoundWhateverItsSpelling() {
        let result = HotkeyEdits.removing("ctrl+opt+left", from: ["ctrl+opt+left": "Safari"], defaults: defaults)
        #expect(result["ctrl+opt+left"] == "")
    }

    private func table(_ hotkeys: [String: String]) -> HotkeyTable {
        HotkeyTable(hotkeys: hotkeys, defaults: defaults, panelHotKey: .default)
    }

    @Test func aTakenKeyReportsWhatHasIt() throws {
        let left = try #require(KeyCombo(parsing: "ctrl+option+left"))
        let t = try #require(KeyCombo(parsing: "cmd+t"))
        #expect(table([:]).owner(of: left) == "window:leftHalf")
        #expect(table(["cmd+t": "Terminal"]).owner(of: t) == "Terminal")
    }

    @Test func aDisabledDefaultIsFree() throws {
        let left = try #require(KeyCombo(parsing: "ctrl+option+left"))
        #expect(table(["ctrl+option+left": ""]).owner(of: left) == nil)
    }
}

@Suite struct SettingsListTests {
    @Test func idsWithNoRowUseNoneOfTheLimit() {
        let offered: Set<String> = ["keepAwake", "sleep", "lock"]
        let chosen = ["keepAwake", "clipboard", "sleep"]
        #expect(OrderedChoice.count(chosen, offered: offered) == 2)
        #expect(OrderedChoice.toggled("lock", in: chosen, limit: 3, offered: offered) == chosen + ["lock"])
    }

    @Test func movingStepsOverIdsWithNoRow() {
        let chosen = ["keepAwake", "clipboard", "sleep"]
        #expect(OrderedChoice.moved("sleep", by: -1, in: chosen, offered: ["keepAwake", "sleep"]) == ["sleep", "clipboard", "keepAwake"])
    }

    @Test func visibilityMatchesAnySpelling() {
        let visibility = Visibility(true, hidden: ["shutdown", "Left Half"])
        #expect(visibility.hides(["shutDown", "Shut Down"]))
        #expect(visibility.hides(["leftHalf", "left half"]))
        #expect(!visibility.hides(["sleep"]))
    }

    @Test func duplicateTilesAreDropped() throws {
        let home = try JSONDecoder().decode(Config.Home.self, from: Data(#"{"tiles": ["sleep", "sleep", "lock"], "tileHeight": 80}"#.utf8))
        #expect(home.tiles == ["sleep", "lock"])
        #expect(home.tileHeight == Config.Home.minimumTileHeight)
    }

    @Test func resetsKeepClipboardRetention() {
        var config = Config()
        config.clipboard.maxAgeDays = 0
        config.clipboard.maxItems = 5000
        config.clipboard.keyword = "cb"
        for reset in [config.resetting(.features), config.resettingAll()] {
            #expect(reset.clipboard.maxAgeDays == 0 && reset.clipboard.maxItems == 5000)
            #expect(reset.clipboard.keyword == Config().clipboard.keyword)
        }
    }

    @Test func aPreviewOnlyReadsTheStartOfALongEntry() {
        let entry = ClipboardEntry(kind: .text, content: "first line\n" + String(repeating: "x", count: 100_000), sourceApp: nil)
        #expect(entry.preview == "first line")
        let oneLine = ClipboardEntry(kind: .text, content: String(repeating: "x", count: 100_000), sourceApp: nil)
        #expect(oneLine.preview == String(repeating: "x", count: 120) + "…")
    }

    @Test func searchSaysWhyAControlIsntShown() throws {
        let entry = { (id: String) in SettingsCatalog.entries.first { $0.id == id }! }
        let nothing = Theme().overrides(dark: false)
        var config = Config()
        #expect(entry("home.tiles").unavailableReason(in: config, decided: nothing) == "Needs the Tiles home screen")
        #expect(entry("home.sections").unavailableReason(in: config, decided: nothing) == nil)
        config.clipboard.enabled = false
        #expect(entry("clipboard.items").unavailableReason(in: config, decided: nothing) == "Turn on Clipboard first")
        config.windows.enabled = false
        #expect(entry("windows.list").unavailableReason(in: config, decided: nothing) == nil)
        #expect(entry("windows.gap").unavailableReason(in: config, decided: nothing) != nil)
        let theme = try JSONDecoder().decode(Theme.self, from: Data(#"{"cornerRadius": 3}"#.utf8))
        let decided = theme.overrides(dark: false)
        #expect(entry("cornerRadius").unavailableReason(in: config, decided: decided) != nil)
        #expect(entry("fieldHeight").unavailableReason(in: config, decided: decided) == nil)
    }
}
