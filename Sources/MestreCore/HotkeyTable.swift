import Foundation

/// The global `hotkeys` section parsed once, layered over built-in defaults (the
/// window layouts). Each entry keeps the user's own spelling so errors can be
/// reported against it. A user entry with an empty target disables a default.
public struct HotkeyTable: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// The key as written in the config file (or the default's canonical form).
        public let text: String
        public let combo: KeyCombo
        /// App name, bundle identifier, command id/title, "window:<layout>" or "feature:<id>".
        public let target: String
        public let isDefault: Bool
    }

    /// Prefix for window layout targets: "window:leftHalf".
    public static let windowPrefix = "window:"

    /// Prefix for targets that open the panel on a feature: "feature:clipboard".
    public static let featurePrefix = "feature:"

    public private(set) var entries: [Entry] = []
    /// Config keys that didn't parse.
    public private(set) var invalid: [String] = []
    /// Config keys whose combo repeats another entry or the panel hotkey; not registered.
    public private(set) var duplicates: [String] = []

    public init(hotkeys: [String: String], defaults: [String: String] = [:], panelHotKey: KeyCombo, keyCodes: [Character: UInt16] = KeyCodeMap.current()) {
        var seen: Set<KeyCombo> = [panelHotKey]
        var userCombos: Set<KeyCombo> = []
        // User entries first: they win every collision with a default.
        for (text, target) in hotkeys.sorted(by: { $0.key < $1.key }) {
            guard let combo = KeyCombo(parsing: text, keyCodes: keyCodes) else {
                invalid.append(text)
                continue
            }
            userCombos.insert(combo)
            guard !target.isEmpty else { continue }  // "": disables the default on this key
            guard seen.insert(combo).inserted else {
                duplicates.append(text)
                continue
            }
            entries.append(Entry(text: text, combo: combo, target: target, isDefault: false))
        }
        for (text, target) in defaults.sorted(by: { $0.key < $1.key }) {
            guard let combo = KeyCombo(parsing: text, keyCodes: keyCodes), !userCombos.contains(combo), seen.insert(combo).inserted else { continue }
            entries.append(Entry(text: text, combo: combo, target: target, isDefault: true))
        }
    }

    /// Entries whose target is a window layout.
    public var windowEntries: [Entry] { entries.filter { $0.target.hasPrefix(Self.windowPrefix) } }

    /// The layout a "window:…" target names, nil for anything else.
    public static func windowLayout(in target: String) -> WindowLayout? {
        guard target.hasPrefix(windowPrefix) else { return nil }
        return WindowLayout(rawValue: String(target.dropFirst(windowPrefix.count)))
    }

    /// The feature id a "feature:…" target names, nil for anything else.
    public static func featureID(in target: String) -> String? {
        guard target.hasPrefix(featurePrefix) else { return nil }
        return String(target.dropFirst(featurePrefix.count))
    }

    /// Targets that match none of `apps`, no window layout, and nothing in `alsoResolves` (commands).
    public func unresolvedTargets(in apps: [AppEntry], alsoResolves: (String) -> Bool = { _ in false }) -> [String] {
        entries.map(\.target).filter { target in
            Self.windowLayout(in: target) == nil && !apps.contains { $0.matches(target: target) } && !alsoResolves(target)
        }
    }
}

public extension AppEntry {
    /// True when `target` is this app's name or bundle identifier, case-insensitively.
    func matches(target: String) -> Bool {
        name.caseInsensitiveCompare(target) == .orderedSame
            || bundleIdentifier?.caseInsensitiveCompare(target) == .orderedSame
    }
}
