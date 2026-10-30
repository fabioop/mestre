import AppKit
import Foundation

/// Everything the user can tune. Lives in a JSON file; every field is optional
/// there and falls back to the default here, so a partial file is valid.
public struct Config: Codable, Equatable, Sendable {
    public struct Search: Codable, Equatable, Sendable {
        /// Folders scanned for .app bundles. "~" expands to the home directory.
        public var appDirectories: [String] = ["/Applications", "~/Applications"]
        /// Also index Apple's built-in apps (/System/Applications and the system cryptex).
        public var includeSystemApps: Bool = false
        /// How many folder levels to descend (2 reaches /Applications/Utilities).
        public var scanDepth: Int = 2
        /// Maximum rows shown in the results list.
        public var maxResults: Int = 8
        /// Re-index as soon as an app folder changes (install, delete, rename).
        public var watchFolders: Bool = true
        /// Fallback periodic re-scan, checked when the panel opens. 0 disables it.
        public var refreshIntervalSeconds: Double = 0

        public init() {}

        enum CodingKeys: String, CodingKey { case appDirectories, includeSystemApps, scanDepth, maxResults, watchFolders, refreshIntervalSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appDirectories = try c.decodeIfPresent([String].self, forKey: .appDirectories) ?? appDirectories
            includeSystemApps = try c.decodeIfPresent(Bool.self, forKey: .includeSystemApps) ?? includeSystemApps
            scanDepth = try c.decodeIfPresent(Int.self, forKey: .scanDepth) ?? scanDepth
            maxResults = try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? maxResults
            watchFolders = try c.decodeIfPresent(Bool.self, forKey: .watchFolders) ?? watchFolders
            refreshIntervalSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? refreshIntervalSeconds)
        }
    }

    public struct Ranking: Codable, Equatable, Sendable {
        /// How strongly launch history lifts an app. 1 = default, 0 = text match only.
        public var usageWeight: Double = 1
        /// Show recently launched apps while the search box is empty.
        public var showRecents: Bool = true
        /// Extra score for apps that are currently running (switching is the common case).
        public var runningBoost: Double = 5

        /// How one provider's rows weigh against the others' when results are merged.
        public struct Weight: Codable, Equatable, Sendable {
            /// Multiplies the match score: 1.2 lifts a provider, 0.8 dampens it. Pinned rows are left alone.
            public var scale: Double = 1
            /// Added to every match score; negative keeps a provider below the others unless it matches well.
            public var bias: Double = 0

            public init(scale: Double = 1, bias: Double = 0) {
                self.scale = scale
                self.bias = bias
            }

            enum CodingKeys: String, CodingKey { case scale, bias }

            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                scale = max(0, try c.decodeIfPresent(Double.self, forKey: .scale) ?? scale)
                bias = try c.decodeIfPresent(Double.self, forKey: .bias) ?? bias
            }

            /// "1.2" or "1.2 -5" (scale, then bias), as Settings shows it; nil for anything else.
            public init?(parsing text: String) {
                let parts = text.split(separator: " ").map { Double($0) }
                guard let first = parts.first, let scale = first, parts.count <= 2, parts.allSatisfy({ $0 != nil }) else { return nil }
                self.init(scale: max(0, scale), bias: parts.count > 1 ? parts[1]! : 0)
            }

            public var text: String {
                bias == 0 ? Self.number(scale) : "\(Self.number(scale)) \(Self.number(bias))"
            }

            private static func number(_ value: Double) -> String {
                value == value.rounded() ? String(Int(value)) : String(value)
            }
        }
        /// System Settings panes sit under apps whatever the match: the bias is larger than
        /// any pane's text score, so an app that matches at all comes first.
        public static let defaultProviders = ["settings": Weight(bias: -200)]
        /// Provider id → weight, over `defaultProviders`; a provider not listed keeps scale 1, bias 0.
        public var providers: [String: Weight] = Ranking.defaultProviders
        /// Milliseconds a provider may take per keystroke before it is reported as slow.
        public var budgetMs: Double = 5

        public init() {}

        enum CodingKeys: String, CodingKey { case usageWeight, showRecents, runningBoost, providers, budgetMs }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            usageWeight = try c.decodeIfPresent(Double.self, forKey: .usageWeight) ?? usageWeight
            showRecents = try c.decodeIfPresent(Bool.self, forKey: .showRecents) ?? showRecents
            runningBoost = try c.decodeIfPresent(Double.self, forKey: .runningBoost) ?? runningBoost
            let listed = try c.decodeIfPresent([String: Weight].self, forKey: .providers) ?? [:]
            providers = Self.defaultProviders.merging(listed) { _, file in file }
            budgetMs = max(0, try c.decodeIfPresent(Double.self, forKey: .budgetMs) ?? budgetMs)
        }

        /// The weight for a provider id, default when unlisted.
        public func weight(for provider: String) -> Weight { providers[provider] ?? Weight() }
    }

    /// The user's key overrides inside the panel: `PanelAction` names or item action
    /// ids ("quit", "reveal"…) mapped to one or more combos. Defaults come from
    /// `ActionTable`, so the file only lists what the user changed.
    public struct Keys: Codable, Equatable, Sendable {
        public var overrides: [String: [String]] = [:]

        public init() {}

        public subscript(name: String) -> [String]? {
            get { overrides[name] }
            set { overrides[name] = newValue }
        }

        public subscript(action: PanelAction) -> [String]? {
            get { overrides[action.rawValue] }
            set { overrides[action.rawValue] = newValue }
        }

        /// Accepts `"quit": ["cmd+w"]` and the shorthand `"quit": "cmd+w"`.
        private enum Combos: Decodable {
            case one(String), many([String])
            var values: [String] {
                switch self {
                case .one(let s): return [s]
                case .many(let a): return a
                }
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .one(s) } else { self = .many(try c.decode([String].self)) }
            }
        }

        public init(from decoder: Decoder) throws {
            overrides = try decoder.singleValueContainer().decode([String: Combos].self).mapValues(\.values)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            try c.encode(overrides)
        }
    }

    /// Size and look of the search panel. Values are clamped on decode so a bad
    /// file can't produce a degenerate or off-screen window.
    public struct Panel: Codable, Equatable, Sendable {
        public enum Material: String, Codable, CaseIterable, Sendable {
            /// Liquid Glass (macOS 26); earlier systems fall back to `popover`.
            case glass, clearGlass
            case popover, hud, sidebar, menu, window, none

            public var isGlass: Bool { self == .glass || self == .clearGlass }
        }

        public var width: Double = 720
        public var fieldHeight: Double = 52
        public var rowHeight: Double = 42
        /// Row icon (app icon or symbol tile), in points.
        public var iconSize: Double = 28
        /// Rows shown before the list scrolls. Capped by `search.maxResults`.
        public var maxVisibleRows: Int = 8
        /// Distance of the panel's top edge from the top of the screen, as a fraction of screen height.
        public var verticalPosition: Double = 0.22
        public var cornerRadius: Double = 12
        public var queryFontSize: Double = 20
        public var material: Material = .glass
        /// The bar under the list: what owns the query on the left, the selected row's keys on the right.
        public var showFooter: Bool = true
        /// When more rows exist than fit, show half of the next one so the overflow is visible.
        public var peekNextRow: Bool = true
        /// How long a footer confirmation ("Path copied") stays; 0 turns them off.
        public var toastSeconds: Double = 1.5
        /// Field and footer only until something is typed: no home screen on an empty query.
        public var compact: Bool = false

        public enum Completion: String, Codable, CaseIterable, Sendable {
            /// Choosing a feature turns it into a chip before the field; what you type is its query.
            case scope
            /// Choosing a feature types its keyword into the field.
            case text
        }
        public var completion: Completion = .scope

        public enum Appearance: String, Codable, CaseIterable, Sendable {
            case system, light, dark
        }
        /// Light or dark panel; "system" follows the system appearance.
        public var appearance: Appearance = .system
        /// Selection and highlight colour: "mestre" (the brand violet, per appearance), "system" or ""
        /// (the system accent), or a hex ("#ff8800") / CSS name.
        public var accentColor: String = "mestre"

        public enum Accent: Equatable, Sendable {
            case system, mestre, custom(ParsedColor)
        }
        /// Mestre's own accent, from the app icon: violet in light, lifted for dark so symbols stay legible.
        public static let mestreAccentLight = ParsedColor(red: 0.42, green: 0.22, blue: 0.70)
        public static let mestreAccentDark = ParsedColor(red: 0.66, green: 0.55, blue: 1.0)

        /// `accentColor` resolved; nil when the value is unreadable (the app then uses the system accent).
        public var accentChoice: Accent? {
            switch accentColor.trimmingCharacters(in: .whitespaces).lowercased() {
            case "", "system": return .system
            case "mestre": return .mestre
            default: return accent.map(Accent.custom)
            }
        }

        public enum Subtitles: String, Codable, CaseIterable, Sendable {
            /// Every row shows its second line.
            case always
            /// A second line that is only metadata (a folder, "Browser", a URL, "alias ff") shows on
            /// the selected row; content (an expression, a keyword, an age) shows on every row.
            case selected
        }
        /// When a row's second line is drawn.
        public var subtitles: Subtitles = .selected

        /// `accentColor` parsed, nil for the system accent or an unreadable value.
        public var accent: ParsedColor? {
            accentColor.isEmpty ? nil : ColorParser.parse(accentColor)
        }

        public init() {}

        enum CodingKeys: String, CodingKey {
            case width, fieldHeight, rowHeight, iconSize, maxVisibleRows, verticalPosition, cornerRadius, queryFontSize, material, appearance, accentColor, subtitles, showFooter, peekNextRow, toastSeconds, compact, completion
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            width = max(200, try c.decodeIfPresent(Double.self, forKey: .width) ?? width)
            fieldHeight = max(30, try c.decodeIfPresent(Double.self, forKey: .fieldHeight) ?? fieldHeight)
            rowHeight = max(20, try c.decodeIfPresent(Double.self, forKey: .rowHeight) ?? rowHeight)
            iconSize = min(rowHeight, max(12, try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? iconSize))
            maxVisibleRows = max(1, try c.decodeIfPresent(Int.self, forKey: .maxVisibleRows) ?? maxVisibleRows)
            verticalPosition = min(0.9, max(0, try c.decodeIfPresent(Double.self, forKey: .verticalPosition) ?? verticalPosition))
            cornerRadius = max(0, try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius)
            queryFontSize = max(8, try c.decodeIfPresent(Double.self, forKey: .queryFontSize) ?? queryFontSize)
            // A misspelt choice falls back to the default rather than rejecting the whole file.
            material = c.decodeChoice(forKey: .material) ?? material
            appearance = c.decodeChoice(forKey: .appearance) ?? appearance
            accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor) ?? accentColor
            subtitles = c.decodeChoice(forKey: .subtitles) ?? subtitles
            showFooter = try c.decodeIfPresent(Bool.self, forKey: .showFooter) ?? showFooter
            peekNextRow = try c.decodeIfPresent(Bool.self, forKey: .peekNextRow) ?? peekNextRow
            toastSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .toastSeconds) ?? toastSeconds)
            compact = try c.decodeIfPresent(Bool.self, forKey: .compact) ?? compact
            completion = c.decodeChoice(forKey: .completion) ?? completion
        }
    }

    /// What the panel shows before anything is typed.
    public struct Home: Codable, Equatable, Sendable {
        public enum Section: String, Codable, CaseIterable, Sendable {
            case recent, features, commands

            /// Heading drawn above the section.
            public var title: String {
                switch self {
                case .recent: return "Recent"
                case .features: return "Features"
                case .commands: return "Commands"
                }
            }

            /// Names as the file or the Settings field spell them: unknown ones are dropped
            /// and repeats collapsed, so rows never appear twice.
            public static func parse(_ names: [String]) -> [Section] {
                var seen: Set<Section> = []
                return names.compactMap { Section(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }.filter { seen.insert($0).inserted }
            }
        }

        /// Sections in order: recent (apps), features (every feature's entry point), commands.
        public var sections: [Section] = Section.allCases
        /// Recently launched apps shown at the top.
        public var recentCount: Int = 5
        /// Feature or command ids to leave out, e.g. ["dictionary", "emptyTrash"].
        public var hidden: [String] = []

        public init() {}

        enum CodingKeys: String, CodingKey { case sections, recentCount, hidden }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let names = try c.decodeIfPresent([String].self, forKey: .sections) { sections = Section.parse(names) }
            recentCount = max(0, try c.decodeIfPresent(Int.self, forKey: .recentCount) ?? recentCount)
            hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? hidden
        }
    }

    public struct Calculator: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Significant digits shown and copied (1–17).
        public var precision: Int = 10

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, precision }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            precision = min(17, max(1, try c.decodeIfPresent(Int.self, forKey: .precision) ?? precision))
        }
    }

    public struct Commands: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Ask before Restart, Shut Down, Log Out and Empty Trash.
        public var confirmDestructive: Bool = true
        /// Command ids to leave out of results, e.g. ["shutDown", "restart"].
        public var hidden: [String] = []

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, confirmDestructive, hidden }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            confirmDestructive = try c.decodeIfPresent(Bool.self, forKey: .confirmDestructive) ?? confirmDestructive
            hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? hidden
        }
    }

    public struct SettingsPanes: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Pane titles or bundle identifiers to leave out, e.g. ["Game Center"].
        public var hidden: [String] = []

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, hidden }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? hidden
        }
    }

    public struct KeepAwake: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// First word that lists the keep-awake options: "awake 45m", "awake until 18:30".
        public var keyword: String = "awake"
        /// Let the display sleep while the Mac is kept awake (sessions then only prevent system sleep).
        public var allowDisplaySleep: Bool = false
        /// Timed options offered after the keyword, in minutes.
        public var durationsMinutes: [Int] = [15, 30, 60, 120, 240]
        /// App names or bundle identifiers that keep the Mac awake while they run.
        public var whileRunningApps: [String] = []
        /// Keep awake whenever the Mac is on AC power.
        public var whileCharging: Bool = false
        /// End any session when the battery drops below this percentage; 0 never does.
        public var endWhenBatteryBelow: Int = 0
        /// Swap the menu-bar icon while a session is active.
        public var menuBarIcon: Bool = true

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, allowDisplaySleep, durationsMinutes, whileRunningApps, whileCharging, endWhenBatteryBelow, menuBarIcon }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            allowDisplaySleep = try c.decodeIfPresent(Bool.self, forKey: .allowDisplaySleep) ?? allowDisplaySleep
            durationsMinutes = (try c.decodeIfPresent([Int].self, forKey: .durationsMinutes) ?? durationsMinutes).filter { $0 > 0 }
            whileRunningApps = try c.decodeIfPresent([String].self, forKey: .whileRunningApps) ?? whileRunningApps
            whileCharging = try c.decodeIfPresent(Bool.self, forKey: .whileCharging) ?? whileCharging
            endWhenBatteryBelow = min(100, max(0, try c.decodeIfPresent(Int.self, forKey: .endWhenBatteryBelow) ?? endWhenBatteryBelow))
            menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? menuBarIcon
        }
    }

    public struct Processes: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// First word that switches the panel to process mode: "kill chrome".
        public var keyword: String = "kill"

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            // One word, lowercased: it is compared with the query's first word.
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
        }
    }

    public struct Shortcuts: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Re-read the shortcut list when the panel opens and it is older than this. 0 = only at launch.
        public var refreshIntervalSeconds: Double = 300

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, refreshIntervalSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            refreshIntervalSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .refreshIntervalSeconds) ?? refreshIntervalSeconds)
        }
    }

    public struct WebSearch: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Search URL with a `{query}` placeholder.
        public var engine: String = "https://duckduckgo.com/?q={query}"

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, engine }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            let url = try c.decodeIfPresent(String.self, forKey: .engine) ?? engine
            engine = url.contains(Quicklink.placeholder) ? url : engine
        }
    }

    public struct Windows: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Points between windows and screen edges.
        public var gap: Double = 0
        /// Layouts to leave out of the results list.
        public var hidden: [String] = []
        /// Show open windows ("Safari — GitHub") as results; needs Accessibility access.
        /// Independent of `enabled`, which covers the layout shortcuts.
        public var listWindows: Bool = true
        /// Don't re-read the window list more often than this when the panel opens.
        public var listRefreshSeconds: Double = 2

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, gap, hidden, listWindows, listRefreshSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            gap = max(0, try c.decodeIfPresent(Double.self, forKey: .gap) ?? gap)
            hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? hidden
            listWindows = try c.decodeIfPresent(Bool.self, forKey: .listWindows) ?? listWindows
            listRefreshSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .listRefreshSeconds) ?? listRefreshSeconds)
        }
    }

    public struct Clipboard: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// First word that lists the history: "clip invoice".
        public var keyword: String = "clip"
        public var maxItems: Int = 500
        /// Entries older than this are dropped; 0 keeps them until maxItems pushes them out.
        public var maxAgeDays: Double = 30
        /// Text larger than this is not recorded (bytes).
        public var maxTextBytes: Int = 1_000_000
        /// How often the pasteboard's change counter is checked.
        public var pollIntervalSeconds: Double = 0.5
        /// Bundle identifiers whose copies are never recorded.
        public var excludeApps: [String] = [
            "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
            "com.lastpass.LastPass", "org.keepassxc.keepassxc", "com.apple.keychainaccess", "com.apple.Passwords",
        ]

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, maxItems, maxAgeDays, maxTextBytes, pollIntervalSeconds, excludeApps }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            maxItems = min(10_000, max(1, try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? maxItems))
            maxAgeDays = max(0, try c.decodeIfPresent(Double.self, forKey: .maxAgeDays) ?? maxAgeDays)
            maxTextBytes = max(1, try c.decodeIfPresent(Int.self, forKey: .maxTextBytes) ?? maxTextBytes)
            pollIntervalSeconds = min(10, max(0.1, try c.decodeIfPresent(Double.self, forKey: .pollIntervalSeconds) ?? pollIntervalSeconds))
            excludeApps = try c.decodeIfPresent([String].self, forKey: .excludeApps) ?? excludeApps
        }
    }

    public struct Snippets: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        public var items: [Snippet] = []
        /// Unicode date format used by `{date}`; `{time}` uses `timeFormat`.
        public var dateFormat: String = "yyyy-MM-dd"
        public var timeFormat: String = "HH:mm"
        public var expansion = Expansion()

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, items, dateFormat, timeFormat, expansion }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            // Repeated names keep the first definition: the name is the identity.
            var names = Set<String>()
            items = (try c.decodeIfPresent([Snippet].self, forKey: .items) ?? []).filter { names.insert($0.name).inserted }
            dateFormat = try c.decodeIfPresent(String.self, forKey: .dateFormat) ?? dateFormat
            timeFormat = try c.decodeIfPresent(String.self, forKey: .timeFormat) ?? timeFormat
            expansion = try c.decodeIfPresent(Expansion.self, forKey: .expansion) ?? expansion
        }
    }

    /// Typing a snippet keyword anywhere replaces it with the snippet. Off by default:
    /// it needs a keyboard event tap (Accessibility) that sees every key you type.
    public struct Expansion: Codable, Equatable, Sendable {
        public var enabled: Bool = false
        /// Bundle identifiers where keywords are never expanded (terminals, password fields).
        public var excludeApps: [String] = []

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, excludeApps }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            excludeApps = try c.decodeIfPresent([String].self, forKey: .excludeApps) ?? excludeApps
        }
    }

    public struct Emoji: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// "emoji fire" lists matches…
        public var keyword: String = "emoji"
        /// …and so does ":fire". Empty disables the shorthand.
        public var prefix: String = ":"
        public var recentCount: Int = 24

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, prefix, recentCount }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? prefix
            recentCount = min(200, max(0, try c.decodeIfPresent(Int.self, forKey: .recentCount) ?? recentCount))
        }
    }

    public struct Files: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// "file report" searches names under `folders`.
        public var keyword: String = "file"
        public var folders: [String] = ["~"]
        public var excludedFolders: [String] = ["~/Library", "~/.Trash"]
        public var maxResults: Int = 20
        /// Pause after the last keystroke before Spotlight is asked.
        public var debounceSeconds: Double = 0.15
        /// Characters typed before Spotlight is asked: one letter would match most of the disk.
        public var minimumLength: Int = 2

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, folders, excludedFolders, maxResults, debounceSeconds, minimumLength }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            folders = try c.decodeIfPresent([String].self, forKey: .folders) ?? folders
            excludedFolders = try c.decodeIfPresent([String].self, forKey: .excludedFolders) ?? excludedFolders
            maxResults = min(100, max(1, try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? maxResults))
            debounceSeconds = min(2, max(0, try c.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? debounceSeconds))
            minimumLength = min(10, max(1, try c.decodeIfPresent(Int.self, forKey: .minimumLength) ?? minimumLength))
        }
    }

    /// Browsing folders by typing "~/…" or "/…".
    public struct Paths: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        public var showHidden: Bool = false
        public var maxResults: Int = 20

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, showHidden, maxResults }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            showHidden = try c.decodeIfPresent(Bool.self, forKey: .showHidden) ?? showHidden
            maxResults = min(200, max(1, try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? maxResults))
        }
    }

    public struct DictionaryLookup: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// "define serendipity".
        public var keyword: String = "define"
        public var maxLines: Int = 6
        /// Pause after the last keystroke before the dictionary is asked (a lookup takes ~20 ms).
        public var debounceSeconds: Double = 0.15

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, maxLines, debounceSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            maxLines = min(20, max(1, try c.decodeIfPresent(Int.self, forKey: .maxLines) ?? maxLines))
            debounceSeconds = min(2, max(0, try c.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? debounceSeconds))
        }
    }

    public struct Bookmarks: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// "bm swift" searches bookmarks…
        public var keyword: String = "bm"
        /// …and with this on, so does every ordinary query (below apps by `penalty`).
        public var searchEverywhere: Bool = false
        public var penalty: Double = 10
        /// Shortest ordinary query that searches bookmarks when `searchEverywhere` is on.
        public var minimumLength: Int = 2
        /// Open in the browser the bookmark came from rather than the default browser.
        public var openInSourceBrowser: Bool = true
        /// Browser ids to skip: chrome, brave, edge, chromium, vivaldi, arc, firefox.
        public var excludeBrowsers: [String] = []

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, searchEverywhere, penalty, minimumLength, openInSourceBrowser, excludeBrowsers }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            searchEverywhere = try c.decodeIfPresent(Bool.self, forKey: .searchEverywhere) ?? searchEverywhere
            penalty = max(0, try c.decodeIfPresent(Double.self, forKey: .penalty) ?? penalty)
            minimumLength = min(10, max(1, try c.decodeIfPresent(Int.self, forKey: .minimumLength) ?? minimumLength))
            openInSourceBrowser = try c.decodeIfPresent(Bool.self, forKey: .openInSourceBrowser) ?? openInSourceBrowser
            excludeBrowsers = try c.decodeIfPresent([String].self, forKey: .excludeBrowsers) ?? excludeBrowsers
        }
    }

    public struct Colors: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Rows shown, in order: hex, rgb, hsl, swiftui.
        public var formats: [String] = ["hex", "rgb", "hsl", "swiftui"]
        /// Treat CSS colour names ("coral", "tan") as colours. Off, so app names stay app searches.
        public var names: Bool = false

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, formats, names }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            formats = (try c.decodeIfPresent([String].self, forKey: .formats) ?? formats).map { $0.lowercased() }
            names = try c.decodeIfPresent(Bool.self, forKey: .names) ?? names
        }
    }

    public struct Paste: Codable, Equatable, Sendable {
        /// Wait after closing the panel before sending ⌘V, so the previous app is key again.
        public var delaySeconds: Double = 0.05
        /// Wait after ⌘V before moving the caret to a snippet's `{cursor}`; slow apps need more.
        public var cursorDelaySeconds: Double = 0.1

        public init() {}

        enum CodingKeys: String, CodingKey { case delaySeconds, cursorDelaySeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            delaySeconds = min(2, max(0, try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? delaySeconds))
            cursorDelaySeconds = min(2, max(0, try c.decodeIfPresent(Double.self, forKey: .cursorDelaySeconds) ?? cursorDelaySeconds))
        }
    }

    public struct Debug: Codable, Equatable, Sendable {
        /// Log hot-path timings (panel show, search, index scan) to the unified log.
        public var logTimings: Bool = false

        public init() {}

        enum CodingKeys: String, CodingKey { case logTimings }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            logTimings = try c.decodeIfPresent(Bool.self, forKey: .logTimings) ?? logTimings
        }
    }

    /// Keyword-triggered scripts that print rows (M2); see `ScriptFilter`.
    public struct Scripts: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        public var items: [ScriptFilter] = []

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, items }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            // A repeated name or keyword keeps the first: both are identities.
            var names = Set<String>(), keywords = Set<String>()
            items = (try c.decodeIfPresent([ScriptFilter].self, forKey: .items) ?? [])
                .filter { !$0.keyword.isEmpty && names.insert($0.name).inserted && keywords.insert($0.keyword).inserted }
        }
    }
    public var scripts = Scripts()

    public struct Onboarding: Codable, Equatable, Sendable {
        /// Show the welcome window at launch. The app sets this to false once it has been
        /// seen; set it back to true to see it again.
        public var showWelcome: Bool = true

        public init() {}

        enum CodingKeys: String, CodingKey { case showWelcome }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            showWelcome = try c.decodeIfPresent(Bool.self, forKey: .showWelcome) ?? showWelcome
        }
    }

    /// Shortcut that toggles the panel, in "option+space" form.
    public var hotKey: KeyCombo = .default
    public var keys = Keys()
    /// Shorthand → app, e.g. "ff": "Firefox". The value is an app name or bundle identifier.
    public var aliases: [String: String] = [:]
    /// Global shortcut → target: an app name or bundle id, a command id or title, or
    /// "window:<layout>". Window layouts have ⌃⌥ defaults; "" on a key disables one.
    public var hotkeys: [String: String] = [:]

    /// The hotkey defaults in force: the window layouts, when window management is on.
    public var hotkeyDefaults: [String: String] { windows.enabled ? WindowLayout.defaultHotkeys : [:] }
    /// Saved links; `{query}` in a URL makes it a search ("gh swift").
    public var quicklinks: [Quicklink] = []

    /// Two-letter keys for commands and features, shown on their rows; typing one puts its row first.
    public struct QuickKeys: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// Key → command or feature id, e.g. "sl": "sleep". Everything else gets a generated key.
        public var keys: [String: String] = [:]

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keys }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keys = (try c.decodeIfPresent([String: String].self, forKey: .keys) ?? keys)
                .reduce(into: [:]) { map, pair in
                    let key = pair.key.trimmingCharacters(in: .whitespaces).lowercased()
                    if key.count == 2 { map[key] = pair.value }
                }
        }
    }
    public var quickKeys = QuickKeys()
    public var panel = Panel()
    public var home = Home()
    public var search = Search()
    public var ranking = Ranking()
    public var calculator = Calculator()
    public var commands = Commands()
    public var settingsPanes = SettingsPanes()
    public var processes = Processes()
    public var keepAwake = KeepAwake()
    public var shortcuts = Shortcuts()
    public var webSearch = WebSearch()
    public var windows = Windows()
    public var clipboard = Clipboard()
    public var snippets = Snippets()
    public var paste = Paste()
    public var emoji = Emoji()
    public var files = Files()
    public var paths = Paths()
    public var dictionary = DictionaryLookup()
    public var bookmarks = Bookmarks()
    public var colors = Colors()
    public var onboarding = Onboarding()
    public var debug = Debug()

    public static let systemAppDirectories = [
        "/System/Applications",
        "/System/Cryptexes/App/System/Applications",
    ]

    public init() {}

    /// Directories to scan, with the system folders appended when enabled and "~" expanded.
    public var resolvedAppDirectories: [URL] {
        var paths = search.appDirectories
        if search.includeSystemApps { paths += Self.systemAppDirectories }
        return paths.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
    }

    /// Every top-level section, in the file's order; `ConfigDocs` documents each one.
    public enum CodingKeys: String, CodingKey, CaseIterable { case hotKey, hotkeys, keys, aliases, quicklinks, quickKeys, panel, home, search, ranking, calculator, commands, settingsPanes, processes, keepAwake, shortcuts, webSearch, windows, clipboard, snippets, paste, emoji, files, paths, dictionary, bookmarks, colors, scripts, onboarding, debug }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try c.decodeIfPresent(String.self, forKey: .hotKey) {
            guard let combo = KeyCombo(parsing: text) else {
                throw DecodingError.dataCorruptedError(forKey: .hotKey, in: c, debugDescription: "Unrecognised shortcut \"\(text)\"")
            }
            hotKey = combo
        }
        keys = try c.decodeIfPresent(Keys.self, forKey: .keys) ?? Keys()
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        hotkeys = try c.decodeIfPresent([String: String].self, forKey: .hotkeys) ?? [:]
        quicklinks = try c.decodeIfPresent([Quicklink].self, forKey: .quicklinks) ?? []
        quickKeys = try c.decodeIfPresent(QuickKeys.self, forKey: .quickKeys) ?? QuickKeys()
        panel = try c.decodeIfPresent(Panel.self, forKey: .panel) ?? Panel()
        home = try c.decodeIfPresent(Home.self, forKey: .home) ?? Home()
        search = try c.decodeIfPresent(Search.self, forKey: .search) ?? Search()
        ranking = try c.decodeIfPresent(Ranking.self, forKey: .ranking) ?? Ranking()
        calculator = try c.decodeIfPresent(Calculator.self, forKey: .calculator) ?? Calculator()
        commands = try c.decodeIfPresent(Commands.self, forKey: .commands) ?? Commands()
        settingsPanes = try c.decodeIfPresent(SettingsPanes.self, forKey: .settingsPanes) ?? SettingsPanes()
        processes = try c.decodeIfPresent(Processes.self, forKey: .processes) ?? Processes()
        keepAwake = try c.decodeIfPresent(KeepAwake.self, forKey: .keepAwake) ?? KeepAwake()
        shortcuts = try c.decodeIfPresent(Shortcuts.self, forKey: .shortcuts) ?? Shortcuts()
        webSearch = try c.decodeIfPresent(WebSearch.self, forKey: .webSearch) ?? WebSearch()
        windows = try c.decodeIfPresent(Windows.self, forKey: .windows) ?? Windows()
        clipboard = try c.decodeIfPresent(Clipboard.self, forKey: .clipboard) ?? Clipboard()
        snippets = try c.decodeIfPresent(Snippets.self, forKey: .snippets) ?? Snippets()
        paste = try c.decodeIfPresent(Paste.self, forKey: .paste) ?? Paste()
        emoji = try c.decodeIfPresent(Emoji.self, forKey: .emoji) ?? Emoji()
        files = try c.decodeIfPresent(Files.self, forKey: .files) ?? Files()
        paths = try c.decodeIfPresent(Paths.self, forKey: .paths) ?? Paths()
        dictionary = try c.decodeIfPresent(DictionaryLookup.self, forKey: .dictionary) ?? DictionaryLookup()
        bookmarks = try c.decodeIfPresent(Bookmarks.self, forKey: .bookmarks) ?? Bookmarks()
        colors = try c.decodeIfPresent(Colors.self, forKey: .colors) ?? Colors()
        scripts = try c.decodeIfPresent(Scripts.self, forKey: .scripts) ?? Scripts()
        onboarding = try c.decodeIfPresent(Onboarding.self, forKey: .onboarding) ?? Onboarding()
        debug = try c.decodeIfPresent(Debug.self, forKey: .debug) ?? Debug()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hotKey.configString, forKey: .hotKey)
        try c.encode(keys, forKey: .keys)
        try c.encode(aliases, forKey: .aliases)
        try c.encode(hotkeys, forKey: .hotkeys)
        try c.encode(quicklinks, forKey: .quicklinks)
        try c.encode(quickKeys, forKey: .quickKeys)
        try c.encode(panel, forKey: .panel)
        try c.encode(home, forKey: .home)
        try c.encode(search, forKey: .search)
        try c.encode(ranking, forKey: .ranking)
        try c.encode(calculator, forKey: .calculator)
        try c.encode(commands, forKey: .commands)
        try c.encode(settingsPanes, forKey: .settingsPanes)
        try c.encode(processes, forKey: .processes)
        try c.encode(keepAwake, forKey: .keepAwake)
        try c.encode(shortcuts, forKey: .shortcuts)
        try c.encode(webSearch, forKey: .webSearch)
        try c.encode(windows, forKey: .windows)
        try c.encode(clipboard, forKey: .clipboard)
        try c.encode(snippets, forKey: .snippets)
        try c.encode(paste, forKey: .paste)
        try c.encode(emoji, forKey: .emoji)
        try c.encode(files, forKey: .files)
        try c.encode(paths, forKey: .paths)
        try c.encode(dictionary, forKey: .dictionary)
        try c.encode(bookmarks, forKey: .bookmarks)
        try c.encode(colors, forKey: .colors)
        try c.encode(scripts, forKey: .scripts)
        try c.encode(onboarding, forKey: .onboarding)
        try c.encode(debug, forKey: .debug)
    }
}

extension KeyedDecodingContainer {
    /// A trigger keyword: the first word, lowercased; the default when missing or blank.
    func decodeKeyword(forKey key: Key, default fallback: String) throws -> String {
        let word = (try decodeIfPresent(String.self, forKey: key) ?? fallback).split(whereSeparator: \.isWhitespace).first
        return word.map { String($0).lowercased() } ?? fallback
    }

    /// A string-backed enum matched case-insensitively; nil when missing or not one of the cases.
    func decodeChoice<E: RawRepresentable>(forKey key: Key) -> E? where E.RawValue == String {
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        return E(rawValue: text.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
