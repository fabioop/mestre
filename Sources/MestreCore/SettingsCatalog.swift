import Foundation

/// The Settings window's map: its pages, its features and every control it has, so the search
/// box can find a setting by name or by what it does. Keys that aren't here are file-only.
public enum SettingsPage: String, CaseIterable, Sendable {
    case general, appearance, features, shortcuts, library

    public var title: String { rawValue.capitalized }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .features: return "square.grid.2x2"
        case .shortcuts: return "keyboard"
        case .library: return "books.vertical"
        }
    }
}

public enum SettingsLibrary: String, CaseIterable, Sendable {
    case quicklinks, snippets, scripts, aliases

    public var title: String { rawValue.capitalized }
}

public enum SettingsFeature: String, CaseIterable, Sendable {
    case clipboard, snippets, calculator, emoji, files, folders, dictionary, bookmarks, colours
    case commands, systemSettings, processes, keepAwake, appleShortcuts, web, windows

    public var title: String {
        switch self {
        case .systemSettings: return "System Settings"
        case .processes: return "Kill Process"
        case .keepAwake: return "Keep Awake"
        case .appleShortcuts: return "Apple Shortcuts"
        case .files: return "File Search"
        default: return rawValue.capitalized
        }
    }

    public var summary: String {
        switch self {
        case .clipboard: return "Everything you copied, searchable"
        case .snippets: return "Saved text, expanded as you type"
        case .calculator: return "Type 2^10 or sqrt(2) into the panel"
        case .emoji: return "Find and paste emoji"
        case .files: return "Find files through Spotlight"
        case .folders: return "Browse by typing ~/ or /"
        case .dictionary: return "Look up a word"
        case .bookmarks: return "Search your browser bookmarks"
        case .colours: return "Convert #ff8800, rgb() and hsl()"
        case .commands: return "Sleep, Lock, Empty Trash and more"
        case .systemSettings: return "Open panes like Bluetooth by name"
        case .processes: return "Quit running processes"
        case .keepAwake: return "Stop the Mac from sleeping"
        case .appleShortcuts: return "Run your shortcuts"
        case .web: return "Open addresses and search the web"
        case .windows: return "Move windows and switch between them"
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .snippets: return "text.quote"
        case .calculator: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .files: return "doc.text.magnifyingglass"
        case .folders: return "folder"
        case .dictionary: return "character.book.closed"
        case .bookmarks: return "bookmark"
        case .colours: return "paintpalette"
        case .commands: return "terminal"
        case .systemSettings: return "slider.horizontal.3"
        case .processes: return "xmark.octagon"
        case .keepAwake: return "cup.and.saucer"
        case .appleShortcuts: return "square.2.layers.3d"
        case .web: return "globe"
        case .windows: return "macwindow.on.rectangle"
        }
    }

    public var isEnabled: WritableKeyPath<Config, Bool> {
        switch self {
        case .clipboard: return \.clipboard.enabled
        case .snippets: return \.snippets.enabled
        case .calculator: return \.calculator.enabled
        case .emoji: return \.emoji.enabled
        case .files: return \.files.enabled
        case .folders: return \.paths.enabled
        case .dictionary: return \.dictionary.enabled
        case .bookmarks: return \.bookmarks.enabled
        case .colours: return \.colors.enabled
        case .commands: return \.commands.enabled
        case .systemSettings: return \.settingsPanes.enabled
        case .processes: return \.processes.enabled
        case .keepAwake: return \.keepAwake.enabled
        case .appleShortcuts: return \.shortcuts.enabled
        case .web: return \.webSearch.enabled
        case .windows: return \.windows.enabled
        }
    }
}

public struct SettingEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let page: SettingsPage
    public var feature: SettingsFeature?
    public var library: SettingsLibrary?
    /// Other words someone might search for.
    public var keywords: [String]

    /// Where the setting lives, as the results list shows it.
    public var path: String {
        ([page.title] + [feature?.title ?? library?.title].compactMap { $0 }).joined(separator: " › ")
    }

    /// Why this setting's control isn't on screen right now, so a search can say so.
    public func unavailableReason(in config: Config, decided: Theme.Overrides) -> String? {
        switch id {
        case "accent" where decided.accent, "material" where decided.material, "cornerRadius" where decided.cornerRadius,
             "fieldHeight" where decided.fieldHeight, "queryFont" where decided.queryFontSize:
            return "Set by the \(config.panel.theme) theme"
        case "home.tiles" where config.home.layout != .tiles, "home.tileHeight" where config.home.layout != .tiles:
            return "Needs the Tiles home screen"
        case "home.sections" where config.home.layout != .list, "home.hidden" where config.home.layout != .list:
            return "Needs the List home screen"
        case "layouts" where !config.windows.enabled:
            return "Turn on Windows first"
        case "snippets.exclude" where config.snippets.expansion.enabled == false:
            return "Turn on text expansion first"
        default:
            break
        }
        guard let feature, id != "feature." + feature.rawValue, !config[keyPath: feature.isEnabled], !keepsWorkingWhileOff else { return nil }
        return "Turn on \(feature.title) first"
    }

    private var keepsWorkingWhileOff: Bool {
        feature?.optionsOutliveSwitch == true && (id == "windows.list" || id == "windows.permission")
    }
}

public extension SettingsFeature {
    /// Some options still apply while the feature is off: `windows.enabled` only covers layouts.
    var optionsOutliveSwitch: Bool { self == .windows }
}

public enum SettingsCatalog {
    private static func general(_ id: String, _ title: String, _ keywords: String = "") -> SettingEntry {
        SettingEntry(id: id, title: title, page: .general, keywords: words(keywords))
    }
    private static func look(_ id: String, _ title: String, _ keywords: String = "") -> SettingEntry {
        SettingEntry(id: id, title: title, page: .appearance, keywords: words(keywords))
    }
    private static func keys(_ id: String, _ title: String, _ keywords: String = "") -> SettingEntry {
        SettingEntry(id: id, title: title, page: .shortcuts, keywords: words(keywords))
    }
    private static func option(_ feature: SettingsFeature, _ id: String, _ title: String, _ keywords: String = "") -> SettingEntry {
        SettingEntry(id: id, title: title, page: .features, feature: feature, keywords: words(keywords))
    }
    private static func words(_ text: String) -> [String] { text.split(separator: " ").map(String.init) }

    public static let entries: [SettingEntry] = fixed + SettingsFeature.allCases.map {
        SettingEntry(id: "feature." + $0.rawValue, title: $0.title, page: .features, feature: $0, keywords: words($0.summary.lowercased()))
    } + SettingsLibrary.allCases.map {
        SettingEntry(id: "library." + $0.rawValue, title: $0.title, page: .library, library: $0, keywords: words(libraryWords($0)))
    }

    private static func libraryWords(_ section: SettingsLibrary) -> String {
        switch section {
        case .quicklinks: return "links url search keyword web"
        case .snippets: return "text template expand keyword"
        case .scripts: return "script filter command shell json"
        case .aliases: return "shorthand nickname app abbreviation"
        }
    }

    private static let fixed: [SettingEntry] = [
        general("hotKey", "Open Mestre", "shortcut hotkey global key spotlight"),
        general("launchAtLogin", "Launch at login", "startup boot start"),
        general("welcome", "Welcome window", "startup onboarding intro"),
        general("version", "Version", "about beta release"),
        general("configFile", "Config file", "json export backup copy move sync another mac defaults"),
        general("apps.system", "Apple's built-in apps", "system include search"),
        general("apps.folders", "App folders", "applications scan directory"),
        general("apps.usage", "Usage influence", "ranking history order frequency"),
        general("apps.recents", "Recent apps when the search is empty", "history ranking"),
        general("import", "Import from Raycast or Alfred", "migrate snippets quicklinks"),
        general("reset", "Reset to defaults", "restore factory clear start over undo backup"),

        look("theme", "Theme", "colours skin style ulm putty tiles micro"),
        look("theme.custom", "Customise a theme", "custom new create add edit own json folder"),
        look("appearance", "Light or dark", "appearance dark mode system night"),
        look("accent", "Accent colour", "highlight selection tint violet"),
        look("material", "Background", "glass blur material transparency popover hud opaque"),
        look("cornerRadius", "Corner radius", "round rounded"),
        look("fieldHeight", "Search field height", "size"),
        look("queryFont", "Search text size", "font query"),
        look("width", "Panel width", "size wide"),
        look("rowHeight", "Row height", "size density compact"),
        look("iconSize", "Icon size", "size"),
        look("rows", "Rows before scrolling", "size visible list"),
        look("results", "Results per search", "maximum count limit"),
        look("position", "Position on screen", "vertical top center"),
        look("subtitles", "Second lines", "subtitle path detail metadata"),
        look("footer", "Footer with key hints", "bar bottom"),
        look("toast", "Confirmation message", "toast copied notification"),
        look("compact", "Compact panel", "minimal hide home"),
        look("completion", "Choosing a feature", "scope chip keyword tab"),
        look("peek", "Half of the next row", "overflow scroll"),
        look("home.layout", "Home screen layout", "tiles list dashboard clock"),
        look("home.tiles", "Tiles", "home dashboard"),
        look("home.tileHeight", "Tile height", "home size"),
        look("home.sections", "Home sections", "recent features commands order"),
        look("home.recent", "Recent apps shown", "home count"),
        look("home.hidden", "Rows on the home screen", "hide hidden remove"),

        keys("hotkeys", "Global shortcuts", "hotkey launch app command feature hyper"),
        keys("layouts", "Window layout shortcuts", "rectangle snap half maximize"),
        keys("panelKeys", "Keys inside the panel", "arrows return navigation actions bindings overrides"),
        keys("quickKeys", "Two-letter quick keys", "shortcut typing generated"),

        option(.clipboard, "clipboard.keyword", "Clipboard keyword"),
        option(.clipboard, "clipboard.items", "Items kept", "history size limit"),
        option(.clipboard, "clipboard.age", "Drop clipboard entries after", "history age expire days"),
        option(.clipboard, "clipboard.exclude", "Never record from these apps", "privacy password exclude ignore"),
        option(.snippets, "snippets.formats", "Date and time format", "placeholder"),
        option(.snippets, "snippets.expansion", "Expand keywords while typing", "text expansion input monitoring"),
        option(.snippets, "snippets.exclude", "Never expand in these apps", "exclude ignore"),
        option(.calculator, "calculator.precision", "Significant digits", "decimals"),
        option(.emoji, "emoji.keyword", "Emoji keyword"),
        option(.emoji, "emoji.recent", "Recent emoji shown"),
        option(.files, "files.keyword", "File search keyword"),
        option(.files, "files.folders", "Folders to search", "spotlight directory"),
        option(.files, "files.exclude", "Folders to skip", "exclude ignore"),
        option(.files, "files.results", "File results", "maximum"),
        option(.folders, "paths.hidden", "Show hidden files", "dotfiles"),
        option(.folders, "paths.results", "Entries listed", "maximum"),
        option(.dictionary, "dictionary.keyword", "Dictionary keyword", "define"),
        option(.dictionary, "dictionary.lines", "Definition lines shown"),
        option(.bookmarks, "bookmarks.keyword", "Bookmarks keyword"),
        option(.bookmarks, "bookmarks.source", "Open in the browser they came from"),
        option(.bookmarks, "bookmarks.everywhere", "Bookmarks in ordinary searches"),
        option(.bookmarks, "bookmarks.browsers", "Browsers to read", "chrome firefox arc brave exclude"),
        option(.colours, "colors.formats", "Colour formats", "hex rgb hsl swiftui"),
        option(.colours, "colors.names", "CSS colour names", "coral"),
        option(.commands, "commands.confirm", "Confirm destructive commands", "restart shut down log out empty trash"),
        option(.commands, "commands.shown", "Commands shown", "hide hidden"),
        option(.systemSettings, "panes.shown", "Panes shown", "hide hidden"),
        option(.processes, "processes.keyword", "Kill keyword"),
        option(.keepAwake, "awake.keyword", "Keep Awake keyword"),
        option(.keepAwake, "awake.display", "Let the display sleep", "caffeinate screen"),
        option(.keepAwake, "awake.menuBar", "Dot on the menu bar icon", "status indicator"),
        option(.keepAwake, "awake.durations", "Timed options", "minutes"),
        option(.keepAwake, "awake.apps", "Stay awake while these apps run", "trigger"),
        option(.keepAwake, "awake.charging", "Stay awake while charging", "power trigger"),
        option(.keepAwake, "awake.battery", "End when battery is low", "power"),
        option(.web, "web.engine", "Search engine", "google duckduckgo kagi bing"),
        option(.windows, "windows.gap", "Gap between windows", "spacing margin"),
        option(.windows, "windows.list", "Open windows as results", "switch"),
        option(.windows, "windows.shown", "Layouts shown", "hide hidden"),
        option(.windows, "windows.permission", "Accessibility access", "permission grant"),
    ]

    /// Every word has to appear somewhere; a match in the title beats one in the keywords.
    public static func search(_ query: String) -> [SettingEntry] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        func score(_ entry: SettingEntry) -> Int? {
            let title = entry.title.lowercased()
            let rest = (entry.keywords + [entry.feature?.title.lowercased(), entry.library?.title.lowercased()].compactMap { $0 }).joined(separator: " ").lowercased()
            guard terms.allSatisfy({ title.contains($0) || rest.contains($0) }) else { return nil }
            if title.hasPrefix(terms[0]) { return 0 }
            return terms.allSatisfy(title.contains) ? 1 : 2
        }
        let scored = entries.compactMap { entry in score(entry).map { (entry, $0) } }
        return scored.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

/// A list where order matters and items can be left out: home sections, tiles, colour rows.
public enum OrderedChoice {
    /// `offered`: what can really be drawn. An id in the file that matches nothing keeps its
    /// place there but uses up none of the limit.
    public static func toggled(_ id: String, in chosen: [String], limit: Int? = nil, offered: Set<String>? = nil) -> [String] {
        if chosen.contains(id) { return chosen.filter { $0 != id } }
        if let limit, count(chosen, offered: offered) >= limit { return chosen }
        return chosen + [id]
    }

    public static func count(_ chosen: [String], offered: Set<String>?) -> Int {
        offered.map { offered in chosen.filter(offered.contains).count } ?? chosen.count
    }

    /// Swaps with the next row on screen, stepping over ids that have no row.
    public static func moved(_ id: String, by offset: Int, in chosen: [String], offered: Set<String>? = nil) -> [String] {
        guard let index = chosen.firstIndex(of: id) else { return chosen }
        var target = index + offset
        while chosen.indices.contains(target), let offered, !offered.contains(chosen[target]) { target += offset }
        guard chosen.indices.contains(target) else { return chosen }
        var result = chosen
        result.swapAt(index, target)
        return result
    }
}

/// Edits to the `hotkeys` map. A default (a window layout) can't be removed from the map, so
/// switching one off or moving it writes an empty target on its key.
public enum HotkeyEdits {
    public static func removing(_ text: String, from hotkeys: [String: String], defaults: [String: String]) -> [String: String] {
        var result = hotkeys
        // The map's key is a spelling: "ctrl+opt+left" still sits on the default "ctrl+option+left".
        let combo = KeyCombo(parsing: text)
        let isDefault = defaults[text] != nil || (combo != nil && defaults.keys.contains { KeyCombo(parsing: $0) == combo })
        result[text] = isDefault ? "" : nil
        return result
    }

    public static func binding(_ target: String, to text: String, replacing old: String?, in hotkeys: [String: String], defaults: [String: String]) -> [String: String] {
        var result = old.map { removing($0, from: hotkeys, defaults: defaults) } ?? hotkeys
        result[text] = target
        return result
    }
}

public extension Config.WebSearch {
    /// The engines Settings offers; any other URL with {query} works from the file or as Custom.
    static let engines: [(name: String, url: String)] = [
        ("DuckDuckGo", "https://duckduckgo.com/?q={query}"),
        ("Google", "https://www.google.com/search?q={query}"),
        ("Bing", "https://www.bing.com/search?q={query}"),
        ("Brave Search", "https://search.brave.com/search?q={query}"),
        ("Kagi", "https://kagi.com/search?q={query}"),
        ("Ecosia", "https://www.ecosia.org/search?q={query}"),
        ("Startpage", "https://www.startpage.com/search?q={query}"),
    ]
}

public extension Config.Snippets {
    static let dateFormats = ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "d MMM yyyy", "EEEE, d MMMM"]
    static let timeFormats = ["HH:mm", "HH:mm:ss", "h:mm a"]
}

public extension Config {
    /// Everything back to its default except what you wrote yourself (quicklinks, snippets,
    /// scripts, aliases) and what a reset shouldn't spring on you: the welcome window coming
    /// back, a change to whether Mestre starts at login, and clipboard history being deleted.
    func resettingAll() -> Config {
        var result = Config()
        result.quicklinks = quicklinks
        result.snippets.items = snippets.items
        result.scripts.items = scripts.items
        result.aliases = aliases
        result.onboarding = onboarding
        result.startup = startup
        result.keepClipboardRetention(of: self)
        return result
    }

    /// Going back to a shorter limit would delete history no Undo can restore.
    private mutating func keepClipboardRetention(of other: Config) {
        clipboard.maxItems = other.clipboard.maxItems
        clipboard.maxAgeDays = other.clipboard.maxAgeDays
    }

    /// One Settings page back to its defaults. The Library is yours, so it has no reset.
    func resetting(_ page: SettingsPage) -> Config {
        var result = self
        let defaults = Config()
        switch page {
        case .general:
            result.hotKey = defaults.hotKey
            result.search.includeSystemApps = defaults.search.includeSystemApps
            result.search.appDirectories = defaults.search.appDirectories
            result.ranking.usageWeight = defaults.ranking.usageWeight
            result.ranking.showRecents = defaults.ranking.showRecents
        case .appearance:
            result.panel = defaults.panel
            result.home = defaults.home
            result.search.maxResults = defaults.search.maxResults
        case .features:
            result.clipboard = defaults.clipboard
            result.keepClipboardRetention(of: self)
            result.calculator = defaults.calculator
            result.emoji = defaults.emoji
            result.files = defaults.files
            result.paths = defaults.paths
            result.dictionary = defaults.dictionary
            result.bookmarks = defaults.bookmarks
            result.colors = defaults.colors
            result.commands = defaults.commands
            result.settingsPanes = defaults.settingsPanes
            result.processes = defaults.processes
            result.keepAwake = defaults.keepAwake
            result.shortcuts = defaults.shortcuts
            result.webSearch = defaults.webSearch
            result.windows = defaults.windows
            result.snippets = defaults.snippets
            result.snippets.items = snippets.items
        case .shortcuts:
            result.hotkeys = defaults.hotkeys
            result.keys = defaults.keys
            result.quickKeys = defaults.quickKeys
        case .library:
            break
        }
        return result
    }
}
