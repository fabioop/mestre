import Foundation

/// How the panel looks, as data: colours, type, corners and a few sizes. A theme can only
/// restyle what the panel already draws. It cannot add information, run code or start a
/// timer, so the search path never knows themes exist. Every key is optional: what a theme
/// leaves out keeps the panel's own look. Colours come as `light` and `dark` palettes, so the
/// theme follows `panel.appearance`; a theme with one palette always draws that one.
public struct Theme: Decodable, Equatable, Sendable {
    public struct Colors: Decodable, Equatable, Sendable {
        public var panel, border, ink, inkSecondary, divider: String?
        public var accent, running: String?
        public var selection, selectionInk, selectionSecondary: String?
        public var iconTile, iconSymbol, selectedIconTile, selectedIconSymbol: String?
        public var keyCap, keyCapInk, keyCapEdge: String?
        /// A cap on the selected row, for a theme whose caps have no fill of their own.
        public var selectedKeyInk: String?
        /// The cap on the footer's Return hint, the one key that gets its own colour.
        public var primaryKey, primaryKeyInk: String?
        /// A filled search field, inset in the panel; without it the field sits on the panel.
        public var field, fieldInk, fieldSecondary, caret: String?
        /// A filled footer bar, inset in the panel.
        public var footer, footerInk, footerSecondary: String?
        /// `ItemKind` raw value → colour: section headers and symbols of that kind.
        public var kinds: [String: String]?
        /// Fills the tile home screen cycles through; their text is black or white, whichever reads.
        public var tiles: [String]?

        public init() {}
    }

    public struct Fonts: Decodable, Equatable, Sendable {
        /// "system", "rounded", "monospaced", "serif", or an installed family name.
        public var ui, query: String?
        /// "light", "regular", "medium", "semibold", "bold" or "heavy".
        public var queryWeight: String?

        public init() {}
    }

    public enum LabelCase: String, Decodable, CaseIterable, Sendable { case upper, lower, none }

    public var appearance: Config.Panel.Appearance?
    public var material: Config.Panel.Material?
    public var cornerRadius, rowRadius, iconRadius, tileRadius: Double?
    public var borderWidth, fieldHeight, queryFontSize: Double?
    /// Section headers and kind labels.
    public var labelCase: LabelCase?
    /// The palette for each mode. One alone pins the theme to that mode.
    public var lightColors, darkColors: Colors?
    /// The one palette of a theme with no `light` or `dark`; `appearance` says which mode it is.
    public var colors = Colors()
    public var fonts = Fonts()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case appearance, material, cornerRadius, rowRadius, iconRadius, tileRadius
        case borderWidth, fieldHeight, queryFontSize, labelCase, light, dark, colors, fonts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A misspelt choice falls back to the default rather than rejecting the whole file.
        appearance = c.decodeChoice(forKey: .appearance)
        material = c.decodeChoice(forKey: .material)
        labelCase = c.decodeChoice(forKey: .labelCase)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius).map { max(0, $0) }
        rowRadius = try c.decodeIfPresent(Double.self, forKey: .rowRadius).map { max(0, $0) }
        iconRadius = try c.decodeIfPresent(Double.self, forKey: .iconRadius).map { max(0, $0) }
        tileRadius = try c.decodeIfPresent(Double.self, forKey: .tileRadius).map { max(0, $0) }
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth).map { max(0, $0) }
        fieldHeight = try c.decodeIfPresent(Double.self, forKey: .fieldHeight).map { max(30, $0) }
        queryFontSize = try c.decodeIfPresent(Double.self, forKey: .queryFontSize).map { max(8, $0) }
        lightColors = try c.decodeIfPresent(Colors.self, forKey: .light)
        darkColors = try c.decodeIfPresent(Colors.self, forKey: .dark)
        colors = try c.decodeIfPresent(Colors.self, forKey: .colors) ?? colors
        fonts = try c.decodeIfPresent(Fonts.self, forKey: .fonts) ?? fonts
    }

    /// The mode a theme with a single palette is stuck in; nil when it can follow the setting.
    private var pinnedAppearance: Config.Panel.Appearance? {
        switch (lightColors != nil, darkColors != nil) {
        case (true, true): return nil
        case (true, false): return .light
        case (false, true): return .dark
        case (false, false): return appearance == .system ? nil : appearance
        }
    }

    /// Whether the panel draws dark: `panel.appearance`, unless the theme has only one palette.
    public func drawsDark(setting: Config.Panel.Appearance, systemIsDark: Bool) -> Bool {
        switch pinnedAppearance ?? setting {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        }
    }

    public func palette(dark: Bool) -> Colors {
        (dark ? darkColors ?? lightColors : lightColors ?? darkColors) ?? colors
    }

    /// Which `panel` keys this theme decides; Settings hides the controls for those alone.
    public struct Overrides: Equatable, Sendable {
        public var accent, material, cornerRadius, fieldHeight, queryFontSize: Bool
    }

    /// A colour that doesn't parse decides nothing: the key keeps the file's value.
    public func overrides(dark: Bool) -> Overrides {
        let colors = palette(dark: dark)
        return Overrides(
            accent: validAccent(colors) != nil,
            // A painted ground needs no blur behind it.
            material: material != nil || colors.panel.flatMap { ColorParser.parse($0) } != nil,
            cornerRadius: cornerRadius != nil,
            fieldHeight: fieldHeight != nil,
            queryFontSize: queryFontSize != nil
        )
    }

    private func validAccent(_ colors: Colors) -> String? {
        colors.accent.flatMap { Config.Panel.Accent(parsing: $0) == nil ? nil : $0 }
    }

    /// The panel settings this theme decides. While a theme is active its values win over the
    /// same `panel` keys; what it leaves out keeps the file's value.
    public func applied(to panel: Config.Panel, dark: Bool) -> Config.Panel {
        var result = panel
        let decided = overrides(dark: dark)
        if let pinnedAppearance { result.appearance = pinnedAppearance }
        if decided.material { result.material = material ?? .none }
        if let cornerRadius { result.cornerRadius = cornerRadius }
        if let fieldHeight { result.fieldHeight = fieldHeight }
        if let queryFontSize { result.queryFontSize = queryFontSize }
        if let accent = validAccent(palette(dark: dark)) { result.accentColor = accent }
        return result
    }
}

/// Finds themes by name: `<config folder>/themes/<name>.json` first, so a user's file can
/// replace a built-in, then the files that ship with the app.
public enum ThemeLibrary {
    /// The look with no theme file at all: the panel's own keys, system colours and glass.
    public static let defaultName = "mestre"
    public static let builtIn = [defaultName, "ulm", "putty", "tiles", "micro"]

    public struct Loaded: Equatable, Sendable {
        public let name: String
        public let theme: Theme
        /// Why the file could not be used; the theme is then the default look.
        public let error: String?
    }

    /// One spelling per theme: "ULM " is "ulm", and an empty name is the default.
    public static func canonicalName(_ name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces).lowercased()
        return name.isEmpty ? defaultName : name
    }

    /// The name comes from a file the user edits: it names a theme, never a path.
    private static func isFileName(_ name: String) -> Bool {
        !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
    }

    public static func userDirectory(configFile: URL) -> URL {
        configFile.deletingLastPathComponent().appendingPathComponent("themes", isDirectory: true)
    }

    /// Reads from disk: call it off the main thread.
    public static func load(_ name: String, userDirectory: URL) -> Loaded {
        let name = canonicalName(name)
        func failure(_ error: String) -> Loaded { Loaded(name: name, theme: Theme(), error: error) }
        guard isFileName(name) else { return failure("“\(name)” is not a theme name.") }
        guard let url = fileURL(for: name, userDirectory: userDirectory) else {
            return name == defaultName ? Loaded(name: name, theme: Theme(), error: nil) : failure("No theme called “\(name)”.")
        }
        do {
            return Loaded(name: name, theme: try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url)), error: nil)
        } catch {
            return failure("\(url.lastPathComponent) could not be read: \(error.localizedDescription)")
        }
    }

    public static func fileURL(for name: String, userDirectory: URL) -> URL? {
        let user = userDirectory.appendingPathComponent(name + ".json")
        if FileManager.default.fileExists(atPath: user.path) { return user }
        return bundledURL(for: name)
    }

    /// Built-ins, then whatever the user's folder adds. Reads the folder: call it off the main thread.
    public static func names(userDirectory: URL) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: userDirectory.path)) ?? []
        let user = files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)).lowercased() }
        return builtIn + user.filter { !builtIn.contains($0) }.sorted()
    }

    /// Writes an editable copy of a theme into the user's folder and returns the copy's name, so
    /// the original stays as it shipped. `mestre` has no file: its copy starts with empty
    /// palettes, which draw the panel's own look until keys are added. A name that isn't a theme
    /// throws, so no blank copy takes its place. Call it off the main thread.
    public static func makeCopy(of name: String, userDirectory: URL) throws -> String {
        let name = canonicalName(name)
        guard isFileName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let source = fileURL(for: name, userDirectory: userDirectory)
        guard source != nil || name == defaultName else { throw CocoaError(.fileNoSuchFile) }
        let data = try source.map { try Data(contentsOf: $0) } ?? Data("{\n  \"light\": {},\n  \"dark\": {}\n}\n".utf8)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let taken = names(userDirectory: userDirectory)
        var copy = name + "-custom", number = 1
        while taken.contains(copy) {
            number += 1
            copy = "\(name)-custom-\(number)"
        }
        try data.write(to: userDirectory.appendingPathComponent(copy + ".json"), options: .withoutOverwriting)
        return copy
    }

    /// The default look has no file of its own.
    private static func bundledURL(for name: String) -> URL? {
        guard name != defaultName, builtIn.contains(name) else { return nil }
        return BundledResource.url(forResource: "theme-\(name)", withExtension: "json")
    }
}

public extension ParsedColor {
    /// WCAG relative luminance, ignoring alpha.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1…21.
    func contrast(with other: ParsedColor) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Black or white, whichever reads better on this colour.
    var readableInk: ParsedColor {
        let black = ParsedColor(red: 0, green: 0, blue: 0), white = ParsedColor(red: 1, green: 1, blue: 1)
        return contrast(with: black) >= contrast(with: white) ? black : white
    }
}

/// The tile home screen's arrow keys, as positions in `results`: the recent apps come first
/// (one row of tiles), then the item tiles (the row under them).
public enum HomeTiles {
    public enum Direction: Sendable { case up, down, left, right }

    public static func move(from index: Int, _ direction: Direction, recents: Int, items: Int) -> Int {
        let count = recents + items
        guard count > 0 else { return 0 }
        let inItems = index >= recents
        switch direction {
        case .left: return max(0, index - 1)
        case .right: return min(count - 1, index + 1)
        case .up:
            guard inItems, recents > 0 else { return index }
            return min(index - recents, recents - 1)
        case .down:
            guard !inItems, items > 0 else { return index }
            return recents + min(index, items - 1)
        }
    }
}
