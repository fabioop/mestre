import AppKit

/// What kind of thing a result is. Shown as a badge. Cases are added with each provider.
public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case app, calculator, command, settings, process, shortcut, quicklink, web, window, clipboard, snippet, emoji, file, definition, bookmark, color, keepAwake, feature, script

    public var label: String {
        switch self {
        case .app: return "App"
        case .calculator: return "Calculator"
        case .command: return "Command"
        case .settings: return "Settings"
        case .process: return "Process"
        case .shortcut: return "Shortcut"
        case .quicklink: return "Quicklink"
        case .web: return "Web"
        case .window: return "Window"
        case .clipboard: return "Clipboard"
        case .snippet: return "Snippet"
        case .emoji: return "Emoji"
        case .file: return "File"
        case .definition: return "Definition"
        case .bookmark: return "Bookmark"
        case .color: return "Color"
        case .keepAwake: return "Keep Awake"
        case .feature: return "Feature"
        case .script: return "Script"
        }
    }

    /// What this kind's second line usually is. A row can override it (see `SearchItem.subtitleRole`).
    public var subtitleRole: SubtitleRole {
        switch self {
        // A place or a category: it only matters once the row is about to be acted on.
        case .app, .file, .settings, .shortcut, .window, .bookmark, .web, .quicklink, .definition:
            return .metadata
        // The second line is the answer, the grammar, or what the user would read anyway.
        case .calculator, .color, .command, .process, .clipboard, .snippet, .emoji, .keepAwake, .feature, .script:
            return .content
        }
    }
}

/// What a row's second line is for. The panel shows `content` on every row and may show
/// `metadata` only on the selected row (`panel.subtitles`), so a list reads as one line per item.
public enum SubtitleRole: Sendable {
    /// Something the user reads to choose: an expression, a keyword, a clipboard entry's age.
    case content
    /// Where or what the item is: a folder, "Browser", "Window", a URL. Also the match reason.
    case metadata
}

/// Something the user can do with a result: plain data, performed by the item's
/// provider. The first action of an item is its default (Return); the rest show in
/// the actions menu and can be bound to keys by id ("quit", "reveal"…).
public struct ItemAction: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// SF Symbol name.
    public let icon: String?
    /// Key combos bound to this action unless `keys` in the config says otherwise ("cmd+q").
    /// The default action of an item needs none: the panel's Return runs it.
    public let defaultKeys: [String]

    public init(id: String, title: String, icon: String? = nil, defaultKeys: [String] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.defaultKeys = defaultKeys
    }

    /// Actions shared by every item that has a file behind it.
    public static let reveal = ItemAction(id: "reveal", title: "Show in Finder", icon: "folder", defaultKeys: ["cmd+return"])
    public static let copyPath = ItemAction(id: "copyPath", title: "Copy Path", icon: "doc.on.doc", defaultKeys: ["cmd+shift+c"])
    /// Actions shared by every item that has a URL behind it.
    public static let openInBrowser = ItemAction(id: "open", title: "Open in Browser", icon: "safari")
    public static let copyURL = ItemAction(id: "copyURL", title: "Copy URL", icon: "doc.on.doc")
    public static let urlActions = [openInBrowser, copyURL]
}

/// One row in the results list, whatever produced it.
public protocol SearchItem {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    /// Whether `subtitle` is content (always shown) or metadata (shown on the selected row only).
    var subtitleRole: SubtitleRole { get }
    var icon: NSImage? { get }
    /// SF Symbol shown when `icon` is nil.
    var iconSymbol: String? { get }
    var kind: ItemKind { get }
    /// Extra strings the fuzzy matcher may match besides the title (aliases, bundle id).
    var keywords: [String] { get }
    /// Shown as a green dot: a running app, an active window…
    var isActive: Bool { get }
    var actions: [ItemAction] { get }
}

public extension SearchItem {
    var subtitle: String? { nil }
    var subtitleRole: SubtitleRole { kind.subtitleRole }
    var iconSymbol: String? { nil }
    var keywords: [String] { [] }
    var isActive: Bool { false }
    var actions: [ItemAction] { [] }
    var defaultAction: ItemAction? { actions.first }
    func action(id: String) -> ItemAction? { actions.first { $0.id == id } }
}

/// A feature's entry on the home screen. Choosing it puts `completion` in the search box
/// ("clip ", ":", "~/"), which is how the feature is reached by typing.
public struct HomeFeature: Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    /// SF Symbol.
    public let symbol: String
    public let completion: String
    /// A command id this feature stands in for on the home screen, so it isn't listed twice.
    public let replacesCommand: String?

    public init(id: String, title: String, subtitle: String, symbol: String, completion: String, replacesCommand: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.completion = completion
        self.replacesCommand = replacesCommand
    }

    /// A feature reached by a keyword: the completion is the keyword and a space.
    public init(id: String, title: String, subtitle: String, symbol: String, keyword: String, replacesCommand: String? = nil) {
        self.init(id: id, title: title, subtitle: subtitle, symbol: symbol, completion: keyword + " ", replacesCommand: replacesCommand)
    }
}

/// The parsed search box contents, computed once per keystroke for all providers.
public struct Query: Equatable, Sendable {
    public let raw: String
    public let text: String
    public let lowercased: String
    public let words: [String]

    public init(_ raw: String) {
        self.raw = raw
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        lowercased = text.lowercased()
        words = lowercased.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public var isEmpty: Bool { text.isEmpty }
    /// First word, lowercased: used by keyword-triggered providers ("g swift" → "g").
    public var firstWord: String? { words.first }
    /// Everything after the first word, trimmed, original casing.
    public var remainder: String {
        guard let range = text.rangeOfCharacter(from: .whitespaces) else { return "" }
        return text[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }
}

/// A result together with the provider that can perform its actions.
public struct ScoredItem: Identifiable {
    /// Score for results that must sit above every fuzzy match (a computed answer).
    public static let pinnedScore = 1_000.0

    public let item: any SearchItem
    /// Set by the provider; the merger may reweigh it (`ranking.providers`).
    public var score: Double
    public unowned let provider: any ResultProvider
    /// The user alias that matched, shown after the title as "Safari (sf)" so it can be learned.
    public let alias: String?
    /// The two-letter quick key shown on the row ("sl"), stamped by the host from `quickKeys`.
    public var quickKey: String?
    /// Heading drawn above this row when it differs from the row before ("Recent", "Features").
    public var section: String?

    /// Namespaced so two providers can describe the same thing (an app and its window).
    public var id: String { "\(provider.id)/\(item.id)" }

    public init(item: any SearchItem, score: Double, provider: any ResultProvider, alias: String? = nil, section: String? = nil) {
        self.item = item
        self.score = score
        self.provider = provider
        self.alias = alias
        self.section = section
    }

    @MainActor
    public func perform(_ action: ItemAction) {
        provider.perform(action, on: item)
    }
}

/// A source of results. Must be fast: every provider runs on the main thread on
/// every keystroke, so anything slow belongs in a precomputed index.
@MainActor
public protocol ResultProvider: AnyObject {
    nonisolated var id: String { get }
    /// Scored results for `query`. Return [] when the provider has nothing to say.
    /// Scores share one scale across providers: a loose fuzzy match is ~20–40,
    /// a prefix match ~50–80, an exact match ~100; use 500+ to force the top.
    func results(for query: Query, limit: Int) -> [ScoredItem]
    /// Runs one of `item.actions`; `item` always came from this provider.
    func perform(_ action: ItemAction, on item: any SearchItem)
    /// Set by the host: closes the panel before an action hands focus to something else.
    var dismiss: (() -> Void)? { get set }
    /// Set by the host: call it when results may have changed behind the user's back.
    var onChange: (() -> Void)? { get set }
    /// Set by the host: replaces the search box contents (completion, e.g. "gh ").
    var replaceQuery: ((String) -> Void)? { get set }
    /// The panel is about to open: a chance to refresh stale data off the main thread.
    func panelWillShow()
    /// The query no longer reaches this provider (another one owns it, or the panel closed).
    func queryLeft()
    /// Rows appended after the ranked results, whatever their scores ("Search the web for…").
    func fallbackResults(for query: Query) -> [ScoredItem]
    /// True when this provider should answer the query alone ("kill chrome", ":fire", "~/Doc").
    func owns(_ query: Query) -> Bool
    /// How this provider presents itself on the home screen (empty query); nil when disabled.
    func homeFeature() -> HomeFeature?
    /// What to show when this provider owns the query and has no rows for it; nil for the generic text.
    func emptyMessage(for query: Query) -> String?
    /// Every action this provider's items can carry, for the action table (titles, symbols,
    /// default keys). Declared statically so the table exists before any search runs.
    nonisolated var declaredActions: [ItemAction] { get }
    /// How the footer names this provider ("Open Windows").
    nonisolated var title: String { get }
    /// What this provider understood from a query it owns, as short chips under the field
    /// ("for 45 min", "~/Documents"); [] when there is nothing to say.
    func chips(for query: Query) -> [String]
}

public extension ResultProvider {
    func owns(_ query: Query) -> Bool { false }
    func homeFeature() -> HomeFeature? { nil }
    func emptyMessage(for query: Query) -> String? { nil }
    func panelWillShow() {}
    func queryLeft() {}
    func fallbackResults(for query: Query) -> [ScoredItem] { [] }
    nonisolated var declaredActions: [ItemAction] { [] }
    func chips(for query: Query) -> [String] { [] }
    /// The id spelled out: "openWindows" → "Open Windows".
    nonisolated var title: String {
        var words = ""
        for character in id {
            if character.isUppercase, !words.isEmpty { words += " " }
            words.append(words.isEmpty ? Character(character.uppercased()) : character)
        }
        return words
    }
}

public extension ActionTable {
    /// The panel actions plus every provider's declared actions, in provider order.
    @MainActor
    init(providers: [any ResultProvider]) {
        self.init(providerActions: providers.map { ($0.id, $0.declaredActions) })
    }
}

public enum ResultMerger {
    /// Merges provider output into one list ordered by score (ties by title, then id),
    /// then appends `fallback` rows so they are always visible, whatever their scores.
    /// `ranking` weighs each provider's scores (`ranking.providers`); pinned rows
    /// (score ≥ `pinnedScore`) keep their score.
    public static func merge(_ lists: [[ScoredItem]], limit: Int, fallback: [ScoredItem] = [], ranking: Config.Ranking = Config.Ranking()) -> [ScoredItem] {
        var all = lists.flatMap { $0 }
        for index in all.indices where all[index].score < ScoredItem.pinnedScore {
            let weight = ranking.weight(for: all[index].provider.id)
            all[index].score = all[index].score * weight.scale + weight.bias
        }
        all.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let byTitle = a.item.title.localizedCaseInsensitiveCompare(b.item.title)
            return byTitle == .orderedSame ? a.id < b.id : byTitle == .orderedAscending
        }
        return Array(all.prefix(max(0, limit - fallback.count))) + fallback
    }
}
