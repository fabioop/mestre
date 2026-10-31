import Foundation
import Testing
@testable import MestreCore

@Suite struct ThemeTests {
    private let noUserFiles = URL(fileURLWithPath: "/nonexistent-mestre-themes")

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mestre-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theDefaultThemeLeavesThePanelAlone() {
        var panel = Config.Panel()
        panel.cornerRadius = 40
        panel.material = .hud
        let loaded = ThemeLibrary.load("mestre", userDirectory: noUserFiles)
        #expect(loaded.error == nil && loaded.theme == Theme())
        #expect(loaded.theme.applied(to: panel, dark: false) == panel)
    }

    @Test func aThemeWinsOnlyForWhatItSets() throws {
        var panel = Config.Panel()
        panel.width = 800
        panel.cornerRadius = 40
        let theme = try JSONDecoder().decode(Theme.self, from: Data(##"{"cornerRadius": 9, "appearance": "dark", "colors": {"panel": "#000", "accent": "#f00"}}"##.utf8))
        let result = theme.applied(to: panel, dark: false)
        #expect(result.cornerRadius == 9 && result.appearance == .dark && result.accentColor == "#f00")
        #expect(result.width == 800 && result.queryFontSize == panel.queryFontSize)
        #expect(result.material == .none)  // a painted ground drops the blur
    }

    @Test func anExplicitMaterialKeepsTheBlurUnderAPaintedGround() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(##"{"material": "hud", "colors": {"panel": "#00000080"}}"##.utf8))
        #expect(theme.applied(to: Config.Panel(), dark: false).material == .hud)
    }

    @Test func aMisspeltChoiceKeepsTheRestOfTheFile() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(#"{"appearance": "sepia", "cornerRadius": 5}"#.utf8))
        #expect(theme.appearance == nil && theme.cornerRadius == 5)
    }

    @Test func aUserFileReplacesABuiltInAndABadOneSaysWhy() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"cornerRadius": 1}"#.utf8).write(to: folder.appendingPathComponent("ulm.json"))
        try Data("not json".utf8).write(to: folder.appendingPathComponent("broken.json"))
        #expect(ThemeLibrary.load("ULM ", userDirectory: folder).theme.cornerRadius == 1)
        let broken = ThemeLibrary.load("broken", userDirectory: folder)
        #expect(broken.error != nil && broken.theme == Theme())
        #expect(ThemeLibrary.names(userDirectory: folder).last == "broken")
    }

    @Test func aNameIsNeverAPath() {
        for name in ["../../secret", "a/b", ".hidden"] {
            let loaded = ThemeLibrary.load(name, userDirectory: noUserFiles)
            #expect(loaded.error != nil && loaded.theme == Theme())
        }
        #expect(ThemeLibrary.load("nosuch", userDirectory: noUserFiles).error != nil)
    }

    @Test func aCopyIsAnEditableThemeBesideTheOriginal() throws {
        let folder = try temporaryFolder().appendingPathComponent("themes")
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let first = try ThemeLibrary.makeCopy(of: "ulm", userDirectory: folder)
        #expect(first == "ulm-custom")
        #expect(ThemeLibrary.load(first, userDirectory: folder).theme == ThemeLibrary.load("ulm", userDirectory: noUserFiles).theme)
        #expect(try ThemeLibrary.makeCopy(of: "ulm", userDirectory: folder) == "ulm-custom-2")
        #expect(ThemeLibrary.names(userDirectory: folder).contains(first))
        // The original still loads as it shipped, and a copy can be copied.
        #expect(ThemeLibrary.load("ulm", userDirectory: folder).theme.cornerRadius == 26)
        #expect(try ThemeLibrary.makeCopy(of: first, userDirectory: folder) == "ulm-custom-custom")
    }

    @Test func aCopyOfTheDefaultStartsEmpty() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = try ThemeLibrary.makeCopy(of: "mestre", userDirectory: folder)
        let loaded = ThemeLibrary.load(copy, userDirectory: folder)
        #expect(loaded.error == nil && loaded.theme.palette(dark: true) == Theme.Colors())
    }

    @Test func theSettingsRoundTrip() throws {
        var config = Config()
        config.panel.theme = "micro"
        config.home.layout = .tiles
        let file = ConfigDocs.file(changes: try ConfigDocs.changes(in: config), notes: [:])
        #expect(try JSONDecoder().decode(Config.self, from: Data(file.utf8)) == config)
        #expect(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).home.layout == .list)
    }

    @Test func aThemeWithBothPalettesFollowsTheSetting() throws {
        let theme = try JSONDecoder().decode(Theme.self, from: Data(##"{"light": {"accent": "#111"}, "dark": {"accent": "#eee"}}"##.utf8))
        #expect(theme.drawsDark(setting: .system, systemIsDark: true))
        #expect(!theme.drawsDark(setting: .system, systemIsDark: false))
        #expect(theme.drawsDark(setting: .dark, systemIsDark: false))
        #expect(!theme.drawsDark(setting: .light, systemIsDark: true))
        #expect(theme.applied(to: Config.Panel(), dark: true).accentColor == "#eee")
        #expect(theme.applied(to: Config.Panel(), dark: false).accentColor == "#111")
        #expect(theme.applied(to: Config.Panel(), dark: true).appearance == .system)
    }

    @Test func aThemeWithOnePaletteStaysInItsMode() throws {
        let onlyDark = try JSONDecoder().decode(Theme.self, from: Data(##"{"dark": {"accent": "#eee"}}"##.utf8))
        #expect(onlyDark.drawsDark(setting: .light, systemIsDark: false))
        #expect(onlyDark.palette(dark: false).accent == "#eee")
        #expect(onlyDark.applied(to: Config.Panel(), dark: true).appearance == .dark)
        let single = try JSONDecoder().decode(Theme.self, from: Data(##"{"appearance": "light", "colors": {"accent": "#111"}}"##.utf8))
        #expect(!single.drawsDark(setting: .dark, systemIsDark: true))
        #expect(single.palette(dark: true).accent == "#111")
        let undeclared = try JSONDecoder().decode(Theme.self, from: Data(##"{"colors": {"accent": "#111"}}"##.utf8))
        #expect(undeclared.drawsDark(setting: .dark, systemIsDark: false))
    }

    /// The text floor from the design system: 4.5:1 for anything to read, 3:1 for a glyph on a key.
    @Test(arguments: ThemeLibrary.builtIn.dropFirst(), [false, true])
    func builtInsParseAndStayReadable(name: String, dark: Bool) throws {
        let loaded = ThemeLibrary.load(name, userDirectory: noUserFiles)
        #expect(loaded.error == nil)
        #expect(loaded.theme.lightColors != nil && loaded.theme.darkColors != nil)
        let colors = loaded.theme.palette(dark: dark)
        func color(_ text: String?, _ key: String) throws -> ParsedColor {
            try #require(text.flatMap { ColorParser.parse($0) }, "\(name): \(key)")
        }
        func check(_ ink: String?, on ground: String?, _ label: String, floor: Double = 4.5) throws {
            guard let ink, let ground else { return }
            let ratio = try color(ink, label).contrast(with: color(ground, label))
            #expect(ratio >= floor, "\(name) \(label): \(ratio)")
        }
        let panel = try color(colors.panel, "panel")
        #expect(panel.alpha == 1)
        // The palette has to be the mode it claims, or system colours around it won't match.
        #expect((panel.luminance < 0.2) == dark, "\(name) panel")
        try check(colors.ink, on: colors.panel, "ink")
        try check(colors.inkSecondary, on: colors.panel, "inkSecondary")
        try check(colors.selectionInk, on: colors.selection, "selectionInk")
        try check(colors.selectionSecondary, on: colors.selection, "selectionSecondary")
        try check(colors.fieldInk, on: colors.field, "fieldInk")
        try check(colors.fieldSecondary, on: colors.field, "fieldSecondary")
        try check(colors.footerInk, on: colors.footer, "footerInk")
        try check(colors.footerSecondary, on: colors.footer, "footerSecondary")
        try check(colors.primaryKeyInk, on: colors.primaryKey, "primaryKeyInk", floor: 3)
        // A cap with no fill shows what is behind it, on the panel and on the selected row.
        let bareCap = try colors.keyCap.map { try color($0, "keyCap").alpha == 0 } ?? false
        try check(colors.keyCapInk, on: bareCap ? colors.panel : colors.keyCap, "keyCapInk")
        try check(colors.selectedKeyInk ?? colors.keyCapInk, on: bareCap ? colors.selection : colors.keyCap, "selected keyCapInk")
        for (kind, value) in colors.kinds ?? [:] {
            #expect(ItemKind(rawValue: kind) != nil, "\(name): unknown kind \(kind)")
            try check(value, on: colors.panel, "kind \(kind)")
        }
        for fill in colors.tiles ?? [] {
            let parsed = try color(fill, "tiles")
            #expect(parsed.contrast(with: parsed.readableInk) >= 4.5, "\(name) tile \(fill)")
        }
    }
}

@Suite struct HomeTilesTests {
    @Test func movesAcrossAndBetweenTheTwoRows() {
        #expect(HomeTiles.move(from: 0, .right, recents: 4, items: 3) == 1)
        #expect(HomeTiles.move(from: 0, .left, recents: 4, items: 3) == 0)
        #expect(HomeTiles.move(from: 6, .right, recents: 4, items: 3) == 6)
        #expect(HomeTiles.move(from: 3, .right, recents: 4, items: 3) == 4)  // wraps onto the next row
        #expect(HomeTiles.move(from: 3, .down, recents: 4, items: 3) == 6)  // clamps to the last tile
        #expect(HomeTiles.move(from: 1, .down, recents: 4, items: 3) == 5)
        #expect(HomeTiles.move(from: 5, .up, recents: 4, items: 3) == 1)
        #expect(HomeTiles.move(from: 1, .up, recents: 4, items: 3) == 1)
        #expect(HomeTiles.move(from: 5, .down, recents: 4, items: 3) == 5)
    }

    @Test func aMissingRowIsNowhereToGo() {
        #expect(HomeTiles.move(from: 1, .up, recents: 0, items: 3) == 1)
        #expect(HomeTiles.move(from: 1, .down, recents: 3, items: 0) == 1)
        #expect(HomeTiles.move(from: 0, .right, recents: 0, items: 0) == 0)
    }
}
