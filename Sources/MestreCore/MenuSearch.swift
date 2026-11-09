import AppKit

// Menu item search: the pure half. The app reads the frontmost app's menu bar through the
// Accessibility API and hands each element to `MenuWalker` through two closures, so the
// walk, the paths, the shortcut glyphs and the ranking are all testable without an app.

public extension Config {
    /// "menu <text>": search and choose the menu bar items of the app in front.
    struct Menus: Codable, Equatable, Sendable {
        public var enabled: Bool = true
        /// First word that searches the menus: "menu export".
        public var keyword: String = "menu"
        /// Menu items also in ordinary searches, below apps by `ranking.providers.menus.bias`. Off by default: it makes every
        /// panel open read the front app's whole menu bar, and an ordinary word ("s", "new")
        /// matches dozens of menu items that would crowd out apps.
        public var searchEverywhere: Bool = false
        /// Read the menus as soon as the panel opens, so they are ready by the time the keyword is
        /// typed. Off by default: window management already grants Accessibility, so this would read
        /// the front app's menu bar on nearly every open; off reads them when the keyword is typed.
        public var readOnOpen: Bool = false
        /// Menu levels read, counting the menu bar's own menus: 1 is File's items, 2 adds
        /// File › Export's, and so on.
        public var maxDepth: Int = 4
        /// Items read at most per app, against menus that list thousands (history, bookmarks).
        public var maxItems: Int = 3000
        /// How long one read may take before it stops with what it has.
        public var readTimeoutSeconds: Double = 2
        /// How long a read is reused when the panel opens again over the same app. Switching apps
        /// always reads again. Items enable and disable as the app's state changes, so keep it short.
        public var cacheSeconds: Double = 5

        public init() {}

        enum CodingKeys: String, CodingKey { case enabled, keyword, searchEverywhere, readOnOpen, maxDepth, maxItems, readTimeoutSeconds, cacheSeconds }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
            keyword = try c.decodeKeyword(forKey: .keyword, default: keyword)
            searchEverywhere = try c.decodeIfPresent(Bool.self, forKey: .searchEverywhere) ?? searchEverywhere
            readOnOpen = try c.decodeIfPresent(Bool.self, forKey: .readOnOpen) ?? readOnOpen
            maxDepth = min(10, max(1, try c.decodeIfPresent(Int.self, forKey: .maxDepth) ?? maxDepth))
            maxItems = max(1, try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? maxItems)
            readTimeoutSeconds = min(30, max(0.1, try c.decodeIfPresent(Double.self, forKey: .readTimeoutSeconds) ?? readTimeoutSeconds))
            cacheSeconds = max(0, try c.decodeIfPresent(Double.self, forKey: .cacheSeconds) ?? cacheSeconds)
        }
    }
}

/// What the walker needs to know about one menu bar item or menu item.
public struct MenuNode<Element> {
    public var title: String
    public var isEnabled: Bool
    /// Already formatted ("⇧⌘E"), nil when the item has none.
    public var shortcut: String?
    /// The menu this item opens, if any.
    public var submenu: Element?

    public init(title: String, isEnabled: Bool = true, shortcut: String? = nil, submenu: Element? = nil) {
        self.title = title
        self.isEnabled = isEnabled
        self.shortcut = shortcut
        self.submenu = submenu
    }
}

/// One menu item that can be chosen: a leaf of the menu tree, enabled when it was read.
public struct MenuEntry<Element>: SearchItem {
    public let id: String
    public let title: String
    /// The menus above the item, top first: ["File", "Export"].
    public let path: [String]
    public let shortcut: String?
    public let element: Element
    /// "File › Export · ⇧⌘E": where the item is, then its shortcut.
    public let subtitle: String?
    /// Title and whole path ("File Export PDF") ready for the matcher (`MenuSearch.results`), so a
    /// keystroke over thousands of items stays in budget.
    let preparedTitle: FuzzyMatcher.Prepared
    let preparedPath: FuzzyMatcher.Prepared

    public init(id: String, title: String, path: [String], shortcut: String?, element: Element) {
        self.id = id
        self.title = title
        self.path = path
        self.shortcut = shortcut
        self.element = element
        subtitle = [path.joined(separator: " › "), shortcut].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        preparedTitle = FuzzyMatcher.Prepared(title)
        preparedPath = FuzzyMatcher.Prepared((path + [title]).joined(separator: " "))
    }

    public var icon: NSImage? { nil }
    public var iconSymbol: String? { "filemenu.and.selection" }
    public var kind: ItemKind { .menuItem }
    public var actions: [ItemAction] { [MenuSearch.press] }
}

extension MenuEntry: Sendable where Element: Sendable {}

public enum MenuWalker {
    /// The choosable items under `bar` (the menu bar's items, Apple menu first), depth first in
    /// menu order. The Apple menu, untitled items (separators), disabled items and their
    /// submenus are left out; an item with a submenu is a container, not a result.
    /// `read` returns nil for an element that can't be read; `items` lists a menu's items.
    /// `shouldStop` is asked before each item, for a deadline.
    public static func walk<Element>(
        bar: [Element],
        maxDepth: Int,
        maxItems: Int,
        read: (Element) -> MenuNode<Element>?,
        items: (Element) -> [Element],
        shouldStop: () -> Bool = { false }
    ) -> [MenuEntry<Element>] {
        var result: [MenuEntry<Element>] = []
        var seen: [String: Int] = [:]
        var stopped = false

        func visit(_ menu: Element, path: [String], depth: Int) {
            for element in items(menu) {
                if result.count >= maxItems || shouldStop() { stopped = true }
                if stopped { return }
                guard let node = read(element) else { continue }
                let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, node.isEnabled else { continue }
                if let submenu = node.submenu {
                    if depth < maxDepth { visit(submenu, path: path + [title], depth: depth + 1) }
                    continue
                }
                var id = (path + [title]).joined(separator: "›")
                let count = seen[id, default: 0]
                seen[id] = count + 1
                if count > 0 { id += "#\(count)" }
                result.append(MenuEntry(id: id, title: title, path: path, shortcut: node.shortcut, element: element))
            }
        }

        for element in bar.dropFirst() {  // the Apple menu is always first
            guard !stopped, let node = read(element), let menu = node.submenu else { continue }
            let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, node.isEnabled else { continue }
            visit(menu, path: [title], depth: 1)
        }
        return result
    }
}

public enum MenuSearch {
    public static let press = ItemAction(id: "press", title: "Choose Menu Item", icon: "filemenu.and.selection")

    /// The rows for `text`, the query after the keyword: every item in menu order when it is
    /// empty, otherwise the best fuzzy matches over title and path (scored by `Ranker.score`, the
    /// path as a keyword).
    @MainActor
    public static func results<Element>(_ entries: [MenuEntry<Element>], matching text: String, limit: Int, provider: any ResultProvider) -> [ScoredItem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ScoredItem.pinned(Array(entries.prefix(limit)), provider: provider)
        }
        let query = Array(trimmed.lowercased())
        var scored: [(index: Int, score: Double)] = []
        for (index, entry) in entries.enumerated() {
            guard let match = Ranker.score(query, title: entry.preparedTitle, keywords: CollectionOfOne(entry.preparedPath)) else { continue }
            scored.append((index, match.score))
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.index < b.index  // menu order, which is already meaningful
        }
        return scored.prefix(limit).map { ScoredItem(item: entries[$0.index], score: $0.score, provider: provider) }
    }
}

/// Turns a menu item's AXMenuItemCmd* attributes into the glyphs its menu shows: "⇧⌘E".
public enum MenuShortcut {
    // kAXMenuItemModifier* masks; no bits means ⌘ alone.
    static let shift = 1, option = 2, control = 4, noCommand = 8

    /// `character` is AXMenuItemCmdChar, `modifiers` AXMenuItemCmdModifiers, `glyph`
    /// AXMenuItemCmdGlyph (a kMenu*Glyph number) and `virtualKey` AXMenuItemCmdVirtualKey.
    public static func format(character: String?, modifiers: Int?, glyph: Int?, virtualKey: Int?) -> String? {
        guard let key = keyLabel(character: character, glyph: glyph, virtualKey: virtualKey) else { return nil }
        let mods = modifiers ?? 0
        var text = ""
        if mods & control != 0 { text += "⌃" }
        if mods & option != 0 { text += "⌥" }
        if mods & shift != 0 { text += "⇧" }
        if mods & noCommand == 0 { text += "⌘" }
        return text + key
    }

    static func keyLabel(character: String?, glyph: Int?, virtualKey: Int?) -> String? {
        if let glyph, glyph != 0, let label = glyphs[glyph] { return label }
        if let character, let scalar = character.unicodeScalars.first {
            if let label = specialCharacters[scalar.value] { return label }
            if (0xF704...0xF726).contains(scalar.value) { return "F\(scalar.value - 0xF704 + 1)" }
            if scalar.value > 0x20, scalar.value != 0x7F, !(0xF700...0xF8FF).contains(scalar.value) {
                return character.uppercased()
            }
        }
        // Only keys with a name: a plain letter's code depends on the keyboard layout.
        if let virtualKey, virtualKey > 0 {
            let label = KeyCombo.label(forKeyCode: UInt16(clamping: virtualKey), characters: nil)
            if !label.hasPrefix("Key ") { return label }
        }
        return nil
    }

    private static let specialCharacters: [UInt32: String] = [
        0x03: "⌤", 0x08: "⌫", 0x09: "⇥", 0x0D: "↩", 0x1B: "⎋", 0x20: "Space", 0x7F: "⌫",
        0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→", 0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘",
        0xF72C: "⇞", 0xF72D: "⇟",
    ]

    /// The kMenu*Glyph numbers from Carbon's Menus.h that menus actually use.
    private static let glyphs: [Int: String] = {
        var table: [Int: String] = [
            0x02: "⇥", 0x03: "⇤", 0x04: "⌤", 0x09: "Space", 0x0A: "⌦", 0x0B: "↩", 0x0C: "↩", 0x0D: "↩",
            0x17: "⌫", 0x1B: "⎋", 0x1C: "⌧", 0x62: "⇞", 0x63: "⇪", 0x64: "←", 0x65: "→", 0x66: "↖",
            0x68: "↑", 0x69: "↘", 0x6A: "↓", 0x6B: "⇟", 0x8C: "⏏", 0x87: "F13", 0x88: "F14", 0x89: "F15",
        ]
        for n in 1...12 { table[0x6E + n] = "F\(n)" }  // kMenuF1Glyph is 0x6F
        return table
    }()
}
