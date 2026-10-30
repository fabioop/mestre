import AppKit

/// Panel-level actions: navigation and the actions menu. Item actions (quit, reveal…)
/// are bound by their `ItemAction.id` instead, so providers can add new ones freely.
public enum PanelAction: String, CaseIterable, Codable, Sendable {
    case moveUp, moveDown, open, close, actions
    /// ⇥: scope a feature or quicklink row, or unfold any other row's actions as chips.
    case complete
    /// ← → between action chips; left to the text field otherwise.
    case moveLeft, moveRight
    /// ⌫ on an empty field leaves the scope chip; left to the text field otherwise.
    case back

    public var title: String {
        switch self {
        case .moveUp: return "Move Up"
        case .moveDown: return "Move Down"
        case .open: return "Open"
        case .close: return "Close"
        case .actions: return "Show Actions"
        case .complete: return "Complete or Unfold"
        case .moveLeft: return "Previous Action"
        case .moveRight: return "Next Action"
        case .back: return "Leave Scope"
        }
    }

    /// SF Symbol.
    public var icon: String {
        switch self {
        case .moveUp: return "arrow.up"
        case .moveDown: return "arrow.down"
        case .open: return "return"
        case .close: return "escape"
        case .actions: return "ellipsis.circle"
        case .complete: return "arrow.right.to.line"
        case .moveLeft: return "arrow.left"
        case .moveRight: return "arrow.right"
        case .back: return "delete.left"
        }
    }

    public var defaultBindings: [String] {
        switch self {
        case .moveUp: return ["up", "ctrl+p"]
        case .moveDown: return ["down", "ctrl+n"]
        case .open: return ["return"]
        case .close: return ["escape"]
        case .actions: return ["cmd+k"]
        case .complete: return ["tab"]
        case .moveLeft: return ["left"]
        case .moveRight: return ["right"]
        case .back: return ["delete"]
        }
    }
}

/// Every action the panel can perform, in one table: the panel's own and each provider's
/// declared item actions, with their titles, symbols, providers and default keys. The
/// `keys` names, the actions menu and the Settings Keys page all read from here, so
/// nothing is reachable by key that cannot be seen and named.
public struct ActionTable: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let icon: String?
        /// Provider ids whose items carry this action. A panel action lists the providers
        /// whose default action shares its id ("open").
        public var providers: [String]
        public var defaultKeys: [String]

        /// Navigation or the menu rather than an action on a result.
        public var isPanel: Bool { PanelAction(rawValue: id) != nil }
    }

    public private(set) var entries: [Entry] = []

    /// The panel actions first, then each provider's actions in order. The first title seen
    /// for an id wins ("Open" over "Switch"); every provider using the id is listed.
    public init(panel: [PanelAction] = PanelAction.allCases, providerActions: [(id: String, actions: [ItemAction])] = []) {
        var index: [String: Int] = [:]
        for action in panel {
            index[action.rawValue] = entries.count
            entries.append(Entry(id: action.rawValue, title: action.title, icon: action.icon, providers: [], defaultKeys: action.defaultBindings))
        }
        for provider in providerActions {
            for action in provider.actions {
                guard let i = index[action.id] else {
                    index[action.id] = entries.count
                    entries.append(Entry(id: action.id, title: action.title, icon: action.icon, providers: [provider.id], defaultKeys: action.defaultKeys))
                    continue
                }
                if !entries[i].providers.contains(provider.id) { entries[i].providers.append(provider.id) }
                if entries[i].defaultKeys.isEmpty { entries[i].defaultKeys = action.defaultKeys }
            }
        }
    }

    public subscript(id: String) -> Entry? {
        entries.first { $0.id == id }
    }
}

/// What a bound key does.
public enum KeyBinding: Equatable, Sendable {
    case panel(PanelAction)
    /// Runs the selected item's action with this id, if it has one.
    case item(String)
}

/// Resolves key events to bindings. Built once per config change from the user's
/// `keys` section layered over the action table's defaults; lookups on the key-down path
/// are a single dictionary read.
public struct KeyBindings: Equatable, Sendable {
    private struct Key: Hashable { let keyCode: UInt32; let modifiers: UInt }

    private var table: [Key: KeyBinding] = [:]
    private var first: [String: String] = [:]
    private var byName: [String: (combos: [String], isOverride: Bool)] = [:]
    /// Every bound name with its combos after layering, for display in Settings.
    public private(set) var effective: [(name: String, combos: [String], isOverride: Bool)] = []
    /// Config strings that didn't parse.
    public private(set) var invalid: [String] = []
    /// Config strings bound to a second action; the first binding wins.
    public private(set) var conflicts: [String] = []
    /// Names in the config that are neither a panel action nor a declared item action. Not bound.
    public private(set) var unknownActions: [String] = []

    /// No bindings at all. Placeholder until the config arrives.
    public static let empty = KeyBindings()

    private init() {}

    public init(keys: Config.Keys, actions: ActionTable = ActionTable(), keyCodes: [Character: UInt16] = KeyCodeMap.current()) {
        unknownActions = keys.overrides.keys.filter { actions[$0] == nil }.sorted()

        // Explicit user keys beat defaults; panel actions beat item actions; then by name.
        func order(_ name: String) -> (Int, Int, String) {
            (keys.overrides[name] == nil ? 1 : 0, actions[name]?.isPanel == true ? 0 : 1, name)
        }
        let bound = actions.entries.filter { !$0.defaultKeys.isEmpty || keys.overrides[$0.id] != nil }.sorted { order($0.id) < order($1.id) }

        for entry in bound {
            let name = entry.id
            let override = keys.overrides[name]
            let combos = override ?? entry.defaultKeys
            effective.append((name, combos, override != nil))
            byName[name] = (combos, override != nil)
            let binding: KeyBinding = PanelAction(rawValue: name).map { .panel($0) } ?? .item(name)
            for text in combos {
                guard let combo = KeyCombo(parsing: text, keyCodes: keyCodes) else {
                    invalid.append(text)
                    continue
                }
                let key = Key(keyCode: combo.keyCode, modifiers: combo.modifierRawValue)
                guard table[key] == nil else {
                    conflicts.append(text)
                    continue
                }
                table[key] = binding
                if first[name] == nil { first[name] = combo.displayString }
            }
        }
        effective.sort { $0.name < $1.name }
    }

    public static func == (lhs: KeyBindings, rhs: KeyBindings) -> Bool {
        lhs.table == rhs.table && lhs.invalid == rhs.invalid && lhs.conflicts == rhs.conflicts && lhs.unknownActions == rhs.unknownActions
    }

    public func binding(forKeyCode keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyBinding? {
        let relevant = modifiers.intersection(KeyCombo.relevantModifiers).rawValue
        return table[Key(keyCode: UInt32(keyCode), modifiers: relevant)]
    }

    public func binding(for event: NSEvent) -> KeyBinding? {
        binding(forKeyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    /// The combos in force for an action name, and whether the user set them; nil when unbound.
    public func combos(for name: String) -> (combos: [String], isOverride: Bool)? {
        byName[name]
    }

    /// Display string of the first binding for a panel action, e.g. "⌘K".
    public func hint(for action: PanelAction) -> String? {
        first[action.rawValue]
    }

    /// Display string for an item action: the panel's Return binding for the default
    /// action, else the first binding of the action's id ("⌘Q" for "quit").
    public func hint(for action: ItemAction, isDefault: Bool) -> String? {
        isDefault ? first[PanelAction.open.rawValue] : first[action.id]
    }
}
